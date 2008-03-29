################################################################################
#
# File:    Job
# Date:    $Date: 2008-03-27 18:23:10 -0500 (Thu, 27 Mar 2008) $
# Version: $Revision: 86 $
#
# A job is a program that can be run.  It is represented as a file in
# the files system whose name is the same as the job name.  The system
# tracks a job's status as well as its return code (unix exit code)
# after it's been run.  Valid statuses are:
# - Waiting
# - Ready
# - Running
# - Success
# - Failure
#
################################################################################

package TaskForest::Job;

use strict;
use warnings;
use Data::Dumper;

################################################################################
#
# Name      : The constructor
# Usage     : my $job = TaskForest::Job->new();
# Purpose   : The Job constructor creates a simple job data
#             structure.  Other classes will set and examine status
#             and return code. 
# Returns   : Self
# Argument  : None
# Throws    : "No job name specified" if the required parameter "name"
#             is not provided. 
#
################################################################################
#
sub new {
    my $arg = shift;
    my $class = (ref $arg) || $arg;

    my $self = {
        name  => '',
        rc  => '',                       # exit code
        status => 'Waiting',
        
    };

    my %args = @_;

    # set up any other parameters that the caller may have passed in 
    #
    foreach my $key (keys %args) {
        $self->{$key} = $args{$key};
    }

    die "No Job name specified" unless $self->{name};

    bless $self, $class;
    return $self;
}

################################################################################
#
# Name      : check
# Usage     : $job->check();
# Purpose   : Checks to see whether the job succeeded.  Implies that
#             it has already run.
# Returns   : 1 if it succeeded.  0 otherwise.
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub check {
    my $self = shift;

    if ($self->{status} eq 'Success') {
        return 1;
    }

    return 0;
}

1;
