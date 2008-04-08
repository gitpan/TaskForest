################################################################################
#
# File:    LogDir
# Date:    $Date: 2008-04-07 19:53:30 -0500 (Mon, 07 Apr 2008) $
# Version: $Revision: 123 $
# 
################################################################################

=head1 NAME

TaskForest::LogDir - Functions related to today's log directory

=head1 SYNOPSIS

 use TaskForest::LogDir;

 my $log_dir = &TaskForest::LogDir::getLogDir("/var/logs/taskforest");
 # $log_dir is created if it does not exist

=head1 DOCUMENTATION

If you're just looking to use the taskforest application, the only
documentation you need to read is that for TaskForest.  You can do this
either of the two ways:

perldoc TaskForest

OR

man TaskForest

If you're a developer and you want to understand the code, I would
recommend that you read the pods in this order:

=over 4

=item *

TaskForest

=item *

TaskForest::Job

=item *

TaskForest::Family

=item *

TaskForest::TimeDependency

=item *

TaskForest::LogDir

=item *

TaskForest::Options

=item *

TaskForest::StringHandleTier

=item *

TaskForest::StringHandle

=back

Finally, read the documentation in the source.  Great efforts have been
made to keep it current and relevant.

=head1 DESCRIPTION

This is a simple package that provides a location for the getLogDir
function that's used in a few places.

=head1 METHODS

=cut

package TaskForest::LogDir;
use strict;
use warnings;
use Carp;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.08';
}

my $log_dir_cached;

# ------------------------------------------------------------------------------
=pod

=over 4

=item getLogDir()

 Usage     : my $log_dir = TaskForest::LogDir::getLogDir($root)
 Purpose   : This method creates a dated subdirectory of its first
             parameter, if that directory doesn't already exist.  
 Returns   : The dated directory
 Argument  : $root - the parent directory of the dated directory
 Throws    : "mkdir $log_dir failed" if the log directory cannot be
             created 

=back

=cut

# ------------------------------------------------------------------------------
sub getLogDir {
    my $log_dir_root = shift;
    if ($log_dir_cached) {
        return $log_dir_cached;
    }
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $mon++;
    $year += 1900;
    my $log_dir = sprintf("$log_dir_root/%4d%02d%02d", $year, $mon, $mday);
    unless (-d $log_dir) {
        if (mkdir $log_dir) {
            # do nothing - succeeded
        }
        else {
            croak "mkdir $log_dir failed in LogDir::getLogDir!\n";
        }
    }
    $log_dir_cached = $log_dir;
    return $log_dir;
}


1;
