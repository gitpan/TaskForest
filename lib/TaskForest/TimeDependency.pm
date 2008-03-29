################################################################################
#
# File:    TimeDependency
# Date:    $Date: 2008-03-23 20:13:19 -0500 (Sun, 23 Mar 2008) $
# Version: $Revision: 85 $
#
# A TimeDependency is an object that a job depends on.  It has a time
# (and time zone) associated with it.  Just as a job can depend on
# another job, a job can also depend on a TimeDependency.  The check()
# function is used to determine whether or not a time dependency has
# been met. 
#
################################################################################
 
package TaskForest::TimeDependency;

use strict;
use warnings;
use Data::Dumper;
use DateTime;


################################################################################
#
# Name      : The constructor
# Usage     : my $td = TaskForest::TimeDependency->new();
# Purpose   : The TimeDependency constructor creates a simple
#             TimeDependency data structure.  Other classes will set
#             and examine status and return code. 
# Returns   : Self
# Argument  : Attributes as a hash.  If a single scalar is provided,
#             then that is considered to be a DateTime object -
#             essentially a copy constructor. 
# Throws    : "TimeDependency does not have a start/end time" 
#
################################################################################
#
sub new {
    my $arg = shift;
    my $class = (ref $arg) || $arg;

    # initialize object with default atttributes
    my $self = {
        start  => '',
        tz  => '',                      
        rc  => '',                      # exit code
        status => 'Waiting',
    };

    my $dt;
    if (scalar(@_) == 1) {
        # assume it's a DateTime object.  We really should die
        # here if ref($dt) ne 'DateTime'
        #
        $dt = shift;
    }
    else {
        my %args = @_;

        # Set the attributes passed in
        #
        foreach my $key (keys %args) {
            $self->{$key} = $args{$key};
        }

        die "TimeDependency does not have a start time" unless $self->{start};
        die "TimeDependency does not have a time zone" unless $self->{tz};

        # create a DateTime object
        #
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        ($hour, $min) = split(/:/, $self->{start});
        $dt = DateTime->new(year      => $year + 1900,
                               month     => $mon + 1,
                               day       => $mday,
                               hour      => $hour,
                               minute    => $min,
                               time_zone => $self->{tz});
    }

    # set the ep attribute to the epoch value of the DateTime object.
    $self->{ep} = $dt->epoch;

    bless $self, $class;
    return $self;
}

################################################################################
#
# Name      : check
# Usage     : $td->check();
# Purpose   : Checks to see whether the time dependency has been met
#             or not. 
# Returns   : 1 if it has been met.  0 otherwise.
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub check {
    my $self = shift;
    my $now = time;

    # If it's already marked as having been met, we just return 1;
    #
    if ($self->{status} eq 'Success') {
        return 1;
    }

    # If it has been met, set status variables and return 1 or 0
    #
    if ($now >= $self->{ep}) {
        $self->{rc} = 0;
        $self->{status} = 'Success';
        return 1;
    }
    else {
        $self->{rc} = 1;
        $self->{status} = 'Waiting';
        return 0;
    }
}
    

1;
