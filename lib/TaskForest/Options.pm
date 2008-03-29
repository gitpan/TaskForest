################################################################################
#
# File:    Options
# Date:    $Date: 2008-03-23 20:13:19 -0500 (Sun, 23 Mar 2008) $
# Version: $Revision: 85 $
#
# This is a convenience class that gets the required and optional
# command line parameters, and uses environment variables if command
# line parameters are not specified.  
#
################################################################################
 
package TaskForest::Options;
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;



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
                   default_timezone  => 's',
                   verbose           => undef,
                   help              => undef,
    );

# These are the required options. The absence of any one of these will
# cause the program to die.
#
my @required_options = qw (run_wrapper log_dir job_dir family_dir);


################################################################################
#
# Name      : getOptions
# Usage     : my $options = &TaskForest::Options::getOptions
# Purpose   : This method returns a list of all the options passed
#             in.  
# Returns   : A hash ref of the options
# Argument  : None
# Throws    : "The following required options are missing"
#             Various exceptions if the parameters passed in are of
#             the wrong format. 
#
################################################################################
#
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
        default_timezone => 'GMT',
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
        die "The following required options are missing: ", join(", ", @missing);
    }
    
    # Untaint each option
    #

    # The booleans are set to 1 or 0
    #
    if ($tainted_options->{once_only}) { $options->{once_only} = 1; } else { $options->{once_only} = 0; } 
    if ($tainted_options->{verbose}) { $options->{verbose} = 1; } else { $options->{verbose} = 0; } 
    if ($tainted_options->{help}) { $options->{help} = 1; } else { $options->{help} = 0; } 

    # The non-booleans are scanned with regexes with the matches being
    # put into $options
    #
    if (defined ($tainted_options->{default_timezone})) {
        if ($tainted_options->{default_timezone} =~ m!^([a-z0-9_/]+)!i) { $options->{default_timezone} = $1; } else { die "Bad default_timezone"; }
    }
    if (defined ($tainted_options->{email_failure_to})) {
        if ($tainted_options->{email_failure_to} =~ m!^([a-z0-9_:\.\@]+)!i) { $options->{email_failure_to} = $1; } else { die "Bad email_failure_to"; }
    }
    if (defined ($tainted_options->{run_wrapper})) {
        if ($tainted_options->{run_wrapper} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $options->{run_wrapper} = $1; } else { die "Bad run_wrapper"; }
    }
    if (defined ($tainted_options->{family_dir})) {
        if ($tainted_options->{family_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $options->{family_dir} = $1; } else { die "Bad family_dir"; }
    }
    if (defined ($tainted_options->{job_dir})) {
        if ($tainted_options->{job_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $options->{job_dir} = $1; } else { die "Bad job_dir"; }
    }
    if (defined ($tainted_options->{log_dir})) {
        if ($tainted_options->{log_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $options->{log_dir} = $1; } else { die "Bad log_dir"; }
    }
    if (defined ($tainted_options->{end_time})) {
        if ($tainted_options->{end_time} =~ /(\d{2}:?\d{2})/) { $options->{end_time} = $1; } else { die "Bad end_time"; }
    }
    $options->{end_time} =~ s/://g;
    if (defined ($tainted_options->{wait_time})) {
        if ($tainted_options->{wait_time} =~ /^(\d+)$/) { $options->{wait_time} = $1; } else { die "Bad wait_time"; }
    }

    
    
    print "options is ", Dumper($options) if $options->{verbose};

    if ($options->{help}) {
        # It's hard to find good help these days.  This needs to be implemented
    }
    
    return $options;
}


