#!/usr/bin/perl
eval 'exec /usr/bin/perl -wS $0 ${1+"$@"}'
  if $running_under_some_shell;

# ---------------------------------------------------------------------------- #
# check_exlibris_system_status.pl - Get Ex Libris System Status Information    #
#                                                                              #
# Version 0.9 2021-05-04                                                       #
# (c) Ulrich Leodolter <ulrich.leodolter@obvsg.at>, https://www.obvsg.at/      #
#                                                                              #
# This program returns Ex Libris system status information via API, the        #
# the information is also available at https://status.exlibrisgroup.com.       #
#                                                                              #
# Nagios compliant status code & message will be generated.                    #
# ---------------------------------------------------------------------------- #

use strict;
use Getopt::Long;
use LWP::UserAgent;
use JSON;
use URI::Escape;

our $TIMEOUT;
our %ERRORS;
eval 'use utils qw(%ERRORS $TIMEOUT)';
if ($@) {
    $TIMEOUT = 20;
    %ERRORS  = (
        'OK'        => 0,
        'WARNING'   => 1,
        'CRITICAL'  => 2,
        'UNKNOWN'   => 3,
        'DEPENDENT' => 4
    );
}

# default
my $PROGNAME = 'check_exlibris_system_status';
my $HOSTNAME = 'exlprod.service-now.com';    # exldev.service-now.com
my $USERNAME = 'APIUser';
my $PASSWORD = '';
my $SERVICE  = 'Primo Central';

my $o_host    = undef;                       # API hostname
my $o_user    = undef;                       # API user
my $o_passwd  = undef;                       # API password
my $o_service = undef
  ; # service internal name (Alma EU02 - Production, Primo Central, bX - Production)
my $o_help    = undef;    # help option
my $o_verb    = undef;    # verbose mode
my $o_details = undef;    # details output
my $o_version = undef;    # version info option
my $o_timeout = undef
  ;    # Timeout to use - note that normally timeout is take from nagios anyway

my $VERSION = '0.9';

sub p_version { print "$PROGNAME version : $VERSION\n"; }

sub print_usage {
    print
"Usage: $0 [-H <host>] [-u <username>] [-p <password>] [-S <service>] [-t <timeout>] [-d] [-v] [-V]\n";
}

sub print_help {
    print_usage();
    print <<EOF;

Check Ex Libris system status https://status.exlibrisgroup.com via API

  -H (--hostname)  = API hostname (exlprod.service-now.com or exldev.service-now.com)
  -u (--username)  = API username (default APIUser)
  -p (--password)  = API password
  -S (--service)   = internal service name (contact Exlibris.Status\@exlibrisgroup.com if unknown)
  -t (--timeout)   = timeout in seconds (default 20)
  -d (--details)   = multiline output including service details
  -v (--verbose)   = debugging output
  -V (--version)
  -h (--help)
EOF
}

# For verbose output
sub verb { my $t = shift; print $t, "\n" if defined($o_verb); }

# parse command line options
sub check_options {
    GetOptions(
        'H|hostname=s' => \$o_host,
        'u|username=s' => \$o_user,
        'p|password=s' => \$o_passwd,
        'S|service=s'  => \$o_service,
        't|timeout=i'  => \$o_timeout,
        'd|details'    => \$o_details,
        'h|help'       => \$o_help,
        'v|verbose'    => \$o_verb,
        'V|version'    => \$o_version,
    );
    if ( defined($o_help) )    { print_help(); exit $ERRORS{"UNKNOWN"} }
    if ( defined($o_version) ) { p_version();  exit $ERRORS{"UNKNOWN"} }

    $HOSTNAME = $o_host    if defined($o_host);
    $USERNAME = $o_user    if defined($o_user);
    $PASSWORD = $o_passwd  if defined($o_passwd);
    $SERVICE  = $o_service if defined($o_service);
    $TIMEOUT  = $o_timeout if defined($o_timeout);
}

# check if service exists
sub check_service_exists {
    my $ua = shift;

    # Create a request
    my $req = HTTP::Request->new(
        'GET',
        'https://'
          . $HOSTNAME
          . '/api/now/table/cmdb_ci_outage?sysparm_fields=cmdb_ci.u_external_name%2Ccmdb_ci.name%2Cshort_description&sysparm_query=cmdb_ciLIKE'
          . uri_escape($SERVICE),
        [ 'Accept' => 'application/json' ]
    );

    my $res = $ua->request($req);
    if ( $res->is_success ) {
        my $json_res = JSON->new->utf8->decode( $res->content );
        map {
            verb(   $_->{'cmdb_ci.name'} . " : "
                  . $_->{'cmdb_ci.u_external_name'} . " : "
                  . $_->{'short_description'} );
        } @{ $json_res->{result} };
        unless ( scalar( @{ $json_res->{result} } ) > 0 ) {
            print "UNKOWN Service: $SERVICE\n";
            exit $ERRORS{"UNKNOWN"};
        }
    }
    else {
        print $res->status_line, "\n";
        exit $ERRORS{"UNKNOWN"};
    }
}

# check upcomming service status
sub check_service_status {
    my $ua = shift;

    my $req = HTTP::Request->new(
        'GET',
        'https://'
          . $HOSTNAME
          . '/api/now/table/cmdb_ci_outage?sysparm_view=mobile&sysparm_fields=cmdb_ci.u_external_name'
          . '%2Cbegin%2Cend%2Cdetails%2Cu_investigating%2Cu_identified%2Cu_in_progress%2Cu_fixed%2Ctype%2Cshort_description&sysparm_query=cmdb_ciLIKE'
          . uri_escape($SERVICE)
          . '^end=NULL',
        [ 'Accept' => 'application/json' ]
    );

    my $status         = $ERRORS{"OK"};
    my $status_line    = '';
    my $status_details = '';

    my $res = $ua->request($req);
    if ( $res->is_success ) {
        my $json_res = JSON->new->utf8->decode( $res->content );
        foreach my $result ( @{ $json_res->{'result'} } ) {
            if ( $result->{'type'} eq 'planned' ) {
                $status = $ERRORS{"WARNING"}
                  if ( $status < $ERRORS{"WARNING"} );
            }
            if ( $result->{'type'} eq 'outage' ) {
                $status = $ERRORS{"ERROR"} if ( $status < $ERRORS{"ERROR"} );
            }
            if ( $result->{'type'} eq 'degradation' ) {
                $status = $ERRORS{"WARNING"}
                  if ( $status < $ERRORS{"WARNING"} );
            }
            if ( $result->{'type'} eq 'info' ) {
                $status = $ERRORS{"OK"} if ( $status < $ERRORS{"OK"} );
            }
            $status_line .= ', ' if ($status_line);
            $status_line .=
              $result->{'cmdb_ci.u_external_name'} . ' ' . $result->{type};
            $status_details .=
              $result->{'cmdb_ci.u_external_name'} . ': ' . $result->{details},
              "\n";
        }
        $status_line .= $SERVICE . ': OK' unless ($status_line);
        print $status_line, "\n";
        print $status_details if ($o_details);
        exit $status;
    }
    else {
        print $res->status_line, "\n";
        exit $ERRORS{"UNKNOWN"};
    }
}

# Get the alarm signal (just in case nagios screws up)
$SIG{'ALRM'} = sub {
    print("ERROR: Alarm signal (Nagios time-out)\n");
    exit $ERRORS{"UNKNOWN"};
};

### MAIN ###

check_options();

# Check global timeout if plugin screws up
if ( defined($TIMEOUT) ) {
    verb("Alarm at $TIMEOUT");
    alarm($TIMEOUT);
}
else {
    verb("no timeout defined : $o_timeout + 10");
    alarm( $o_timeout + 10 );
}

my $ua = LWP::UserAgent->new;
$ua->agent("check-exlibris-system-status/$VERSION");
$ua->credentials( "$HOSTNAME:443", "Service-now", $USERNAME, $PASSWORD );

check_service_exists($ua);
check_service_status($ua);

# end
