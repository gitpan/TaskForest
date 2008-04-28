################################################################################
#
# File:    Mark
# Date:    $Date: 2008-04-25 08:22:51 -0500 (Fri, 25 Apr 2008) $
# Version: $Revision: 128 $
# 
################################################################################

=head1 NAME

TaskForest::Rerun - Functions related to rerunning a job

=head1 SYNOPSIS

 use TaskForest::Rerun;

 &TaskForest::Rerun::rerun($family_name, $job_name)

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

This is a simple package that provides a location for the mark
function, so that it can be used in the test scripts as well. 

=head1 METHODS

=cut

package TaskForest::Mark;
use strict;
use warnings;
use Carp;
use File::Copy;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.09';
}

# ------------------------------------------------------------------------------
=pod

=over 4

=item mark()

 Usage     : mark($family_name, $job_name, $log_dir, $status)
 Purpose   : Mark the specified job as success or failure.  This job
             only changes the name of the status file:
             $family_name.$job_name.[01].  The actual contents of the
             file, the original return code is not changed.  The file
             name is what is used to determine job dependencies. 
 Returns   : Nothing
 Arguments : $family_name - the family name
             $job_name - the job name
             $log_dir - the root log directory
             $status - "Success" or "Failure".  Case does not matter. 
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub mark {
    my ($family_name, $job_name, $log_dir, $status) = @_;

    my $rc_file      = "$log_dir/$family_name.$job_name.";
    my $new_rc_file;
    
    if ($status eq 'success') {
        $new_rc_file = $rc_file . "0";
        $rc_file .= '1';
    }
    else { 
        $new_rc_file = $rc_file . "1";
        $rc_file .= '0';
    }
    
    if (-e $new_rc_file) {
        carp("$family_name.$job_name is already marked $status.  Not doing anything.");
    }
    else {
        move($rc_file, $new_rc_file) || confess ("couldn't move $rc_file to $new_rc_file: $!");
    }
    
}

1;
