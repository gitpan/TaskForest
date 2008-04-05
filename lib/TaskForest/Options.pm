################################################################################
#
# File:    Options
# Date:    $Date: 2008-04-04 23:16:41 -0500 (Fri, 04 Apr 2008) $
# Version: $Revision: 117 $
#

=head1 NAME

TaskForest::Options - Get options from command line and/or environment

=head1 SYNOPSIS

 use TaskForest::Options;

 my $o = &TaskForest::Options::getOptions();
 # the above command will die if required options are not present

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

This is a convenience class that gets the required and optional
command line parameters, and uses environment variables if command
line parameters are not specified.  

=head1 METHODS

=cut

package TaskForest::Options;
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Carp;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.06';
}

# This is the main data structure that stores the options
our $options = {};

# This is a list of all options that are accepted, optional and
# required.  The values of the hash are the parameters passed to
# Getopts::Long if the corresponding option stores a value, or undef
# if the parameter represents a boolean value
#
my %all_options = (end_time          => 's',
                   wait_time         => 's',
                   log_dir           => 's',
                   once_only         => undef, 
                   job_dir           => 's',
                   family_dir        => 's',
                   run_wrapper       => 's',
                   email_failure_to  => 's',
                   verbose           => undef,
                   help              => undef,
    );

# These are the required options. The absence of any one of these will
# cause the program to die.
#
my @required_options = qw (run_wrapper log_dir job_dir family_dir);


# ------------------------------------------------------------------------------
=pod

=over 4

=item getOptions()

 Usage     : my $options = &TaskForest::Options::getOptions
 Purpose   : This method returns a list of all the options passed
             in.  
 Returns   : A hash ref of the options
 Argument  : None
 Throws    : "The following required options are missing"
             Various exceptions if the parameters passed in are of
             the wrong format. 

=back

=cut

# ------------------------------------------------------------------------------
sub getOptions {

    # If the options hash is already populated, just return it 
    return $options if (keys %$options);

    # This hash is defined within the function and not in file scope
    # because we want to allow the environment variables to be
    # overwritten within the constructor of the TaskForest.
    #
    # The environment contains the default values of the required
    # options if they're not specified on the command line.
    #
    my $default_options = {
        end_time  => '2355',
        wait_time => 60,
        run_wrapper => $ENV{TF_RUN_WRAPPER},
        log_dir => $ENV{TF_LOG_DIR},
        family_dir => $ENV{TF_FAMILY_DIR},
        job_dir => $ENV{TF_JOB_DIR},
        
    };

    # As options are first retrieved, they're considered tainted and
    # stored in this hash.  Upon untainting they're stred in $options.
    #
    my $tainted_options = {};

    # Every option starts of as undef
    #
    foreach my $option (keys %all_options) {
        $tainted_options->{$option} = undef;
    }

    # Get the command line options into $tainted_options
    #
    GetOptions($tainted_options, map { if ($all_options{$_}) { "$_=$all_options{$_}"} else { $_ } } (keys %all_options));

    if ($tainted_options->{help}) {
        showHelp();
        exit 0;
    } 
    
    # get default options
    #
    foreach my $option (keys %$default_options) { 
        if (!defined($tainted_options->{$option})) {
            $tainted_options->{$option} = $default_options->{$option};
        }
    }

    # Make sure all required options are present
    my @missing = ();
    foreach my $req (@required_options) {
        unless ($tainted_options->{$req}) {
            push (@missing, $req);
        }
    }
    if (@missing) {
        croak "The following required options are missing: ", join(", ", @missing);
    }
    
    # Untaint each option
    #

    # The booleans are set to 1 or 0
    #
    if ($tainted_options->{once_only}) { $options->{once_only} = 1; } else { $options->{once_only} = 0; } 
    if ($tainted_options->{verbose}) { $options->{verbose} = 1; } else { $options->{verbose} = 0; } 

    # The non-booleans are scanned with regexes with the matches being
    # put into $options
    #
    if (defined ($tainted_options->{email_failure_to})) {
        if ($tainted_options->{email_failure_to} =~ m!^([a-z0-9_:\.\@]+)!i) { $options->{email_failure_to} = $1; } else { croak "Bad email_failure_to"; }
    }
    if (defined ($tainted_options->{run_wrapper})) {
        if ($tainted_options->{run_wrapper} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $options->{run_wrapper} = $1; } else { croak "Bad run_wrapper"; }
    }
    if (defined ($tainted_options->{family_dir})) {
        if ($tainted_options->{family_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $options->{family_dir} = $1; } else { croak "Bad family_dir"; }
    }
    if (defined ($tainted_options->{job_dir})) {
        if ($tainted_options->{job_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $options->{job_dir} = $1; } else { croak "Bad job_dir"; }
    }
    if (defined ($tainted_options->{log_dir})) {
        if ($tainted_options->{log_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $options->{log_dir} = $1; } else { croak "Bad log_dir"; }
    }
    if (defined ($tainted_options->{end_time})) {
        if ($tainted_options->{end_time} =~ /(\d{2}:?\d{2})/) { $options->{end_time} = $1; } else { croak "Bad end_time"; }
    }
    $options->{end_time} =~ s/://g;
    if (defined ($tainted_options->{wait_time})) {
        if ($tainted_options->{wait_time} =~ /^(\d+)$/) { $options->{wait_time} = $1; } else { croak "Bad wait_time"; }
    }

    
    print "options is ", Dumper($options) if $options->{verbose};

    
    return $options;
}


# ------------------------------------------------------------------------------
=pod

=over 4

=item showHelp()

 Usage     : showHelp()
 Purpose   : This method prints help text
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub showHelp {
    print qq^
USAGE
      To run the main taskforest dependency checker, do one of the following:

      export TF_JOB_DIR=/foo/jobs
      export TF_LOG_DIR=/foo/logs
      export TF_FAMILY_DIR=/foo/families
      export TF_RUN_WRAPPER=/foo/bin/run
      taskforest

      OR

      taskforest -run_wrapper=/foo/bin/run \
        --log_dir=/foo/logs \
        --job_dir=/foo/jobs \
        --family_dir=/foo/families

      All jobs will run as the user who invoked taskforest.

      To get the status of all currently running and recently run jobs,
      enter the following command:

      status

For more detailed documentation, enter:

man TaskForest

or

perldoc TaskForest
 
^;
}
