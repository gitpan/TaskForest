################################################################################
#
# $Id: Options.pm 132 2009-03-05 01:32:59Z aijaz $
#
################################################################################

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
use Config::General qw(ParseConfig);
use Log::Log4perl qw(:levels);

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.18';
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
                   collapse          => undef, 
                   job_dir           => 's',
                   family_dir        => 's',
                   run_wrapper       => 's',
                   email_failure_to  => 's',
                   verbose           => undef,
                   help              => undef,
                   config_file       => 's',
                   chained           => undef,
                   log_threshold     => 's',
                   log               => undef,
                   log_file          => 's',
                   err_file          => 's',
                   log_status        => undef,
                   ignore_regex      => 's@',
                   default_time_zone => 's',
                   date              => 's',
    );

# These are the required options. The absence of any one of these will
# cause the program to die.
#
my @required_options = qw (run_wrapper log_dir job_dir family_dir);

my $command_line_read = 0;

my $command_line_options = undef;


# ------------------------------------------------------------------------------
=pod

=over 4

=item getConfig()

 Usage     : my $config = &TaskForest::Options::getConfig($file)
 Purpose   : This method reads a config file
 Returns   : A hash ref of the options specified in the config file
 Argument  : The name of the config file
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub getConfig {
    my $config_file = shift;
    my %config = ParseConfig(-ConfigFile => $config_file);
    return \%config;
}

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
    my $reread = shift;

    # If the options hash is already populated, just return it 
    if ((not defined $reread) and keys(%$options)) {
        return $options;
    }

    my $new_options = {};

    if (! defined($command_line_options)) {
        # never do this more than once
        $command_line_options = {};
        GetOptions($command_line_options, map { if ($all_options{$_}) { "$_=$all_options{$_}"} else { $_ } } (keys %all_options));
    }

    # As options are first retrieved, they're considered tainted and
    # stored in this hash.  Upon untainting they're stored in $options.
    #
    my $tainted_options = {};

    # Every option starts of as undef
    foreach my $option (keys %all_options) { $tainted_options->{$option} = undef; }
    # handle multiple value options specially
    #$tainted_options->{ignore_regex} = [];

    # Then it gets the command line value
    foreach my $option (keys %all_options) { $tainted_options->{$option} = $command_line_options->{$option}; }

    # Then it gets the environment variable value, if necessary
    foreach my $option (keys %all_options) { $tainted_options->{$option} = $ENV{"TF_".uc($option)} unless defined $tainted_options->{$option} }

    # Then it gets the config file value if necessary
    my $config;
    if ($tainted_options->{config_file}) {
        my $config_file = $tainted_options->{config_file};
        $config_file =~ s/;//g;
        $config = getConfig($config_file);
    }
    foreach my $option (keys %all_options) { $tainted_options->{$option} = $config->{$option} unless defined $tainted_options->{$option} }

    # Finally, pick a default value if necessary
    $tainted_options->{wait_time}         = 60                unless defined $tainted_options->{wait_time};
    $tainted_options->{end_time}          = '2355'            unless defined $tainted_options->{end_time};
    $tainted_options->{once_only}         = 0                 unless defined $tainted_options->{once_only};
    $tainted_options->{verbose}           = 0                 unless defined $tainted_options->{verbose};
    $tainted_options->{collapse}          = 0                 unless defined $tainted_options->{collapse};
    $tainted_options->{chained}           = 0                 unless defined $tainted_options->{chained};
    $tainted_options->{log}               = 0                 unless defined $tainted_options->{log};
    $tainted_options->{log_threshold}     = 'info'            unless defined $tainted_options->{log_threshold};
    $tainted_options->{log_file}          = "stdout"          unless defined $tainted_options->{log_file};
    $tainted_options->{err_file}          = "stderr"          unless defined $tainted_options->{err_file};
    $tainted_options->{log_status}        = 0                 unless defined $tainted_options->{log_status};
    $tainted_options->{ignore_regex}      = []                unless defined $tainted_options->{ignore_regex};
    $tainted_options->{default_time_zone} = 'America/Chicago' unless defined $tainted_options->{default_time_zone};
    $tainted_options->{date}              = ''                unless defined $tainted_options->{date};

    # show help
    if ($tainted_options->{help}) {
        showHelp();
        exit 0;
    }

    # Make sure all required options are present
    my @missing = ();
    foreach my $req (@required_options) {
        unless ($tainted_options->{$req}) {
            push (@missing, $req);
        }
    }
    if (@missing) {
        # TODO: check for required parameters
        croak "The following required options are missing: ", join(", ", @missing);
    }
    
    # Untaint each option
    #
    # The booleans are set to 1 or 0
    #
    if ($tainted_options->{once_only})       { $new_options->{once_only}       = 1; } else { $new_options->{once_only}       = 0; } 
    if ($tainted_options->{collapse})        { $new_options->{collapse}        = 1; } else { $new_options->{collapse}        = 0; } 
    if ($tainted_options->{verbose})         { $new_options->{verbose}         = 1; } else { $new_options->{verbose}         = 0; } 
    if ($tainted_options->{chained})         { $new_options->{chained}         = 1; } else { $new_options->{chained}         = 0; } 
    if ($tainted_options->{log})             { $new_options->{log}             = 1; } else { $new_options->{log}             = 0; } 

    # The non-booleans are scanned with regexes with the matches being
    # put into $new_options
    #
    if (defined ($tainted_options->{email_failure_to})) {
        if ($tainted_options->{email_failure_to} =~ m!^([a-z0-9_:\.\@]+)!i) { $new_options->{email_failure_to} = $1; } else { croak "Bad email_failure_to"; }
    }
    if (defined ($tainted_options->{run_wrapper})) {
        if ($tainted_options->{run_wrapper} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $new_options->{run_wrapper} = $1; } else { croak "Bad run_wrapper"; }
    }
    if (defined ($tainted_options->{family_dir})) {
        if ($tainted_options->{family_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $new_options->{family_dir} = $1; } else { croak "Bad family_dir"; }
    }
    if (defined ($tainted_options->{job_dir})) {
        if ($tainted_options->{job_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $new_options->{job_dir} = $1; } else { croak "Bad job_dir"; }
    }
    if (defined ($tainted_options->{log_dir})) {
        if ($tainted_options->{log_dir} =~ m!^([a-z0-9/_:\\\.\-]+)!i) { $new_options->{log_dir} = $1; } else { croak "Bad log_dir"; }
    }
    if (defined ($tainted_options->{end_time})) {
        if ($tainted_options->{end_time} =~ /(\d{2}:?\d{2})/) { $new_options->{end_time} = $1; } else { croak "Bad end_time"; }
    }
    $new_options->{end_time} =~ s/://g;
    if (defined ($tainted_options->{wait_time})) {
        if ($tainted_options->{wait_time} =~ /^(\d+)$/) { $new_options->{wait_time} = $1; } else { croak "Bad wait_time"; }
    }
    if (defined ($tainted_options->{log_threshold})) {
        if ($tainted_options->{log_threshold} =~ m!^([a-z0-9_:\.\@]+)!i) { $new_options->{log_threshold} = $1; } else { croak "Bad log_threshold"; }
    }
    if (defined ($tainted_options->{log_file})) {
        if ($tainted_options->{log_file} =~ m!^([a-z0-9_:\.\-]+)!i) { $new_options->{log_file} = $1; } else { croak "Bad log_file"; }
    }
    if (defined ($tainted_options->{err_file})) {
        if ($tainted_options->{err_file} =~ m!^([a-z0-9_:\.\-]+)!i) { $new_options->{err_file} = $1; } else { croak "Bad err_file"; }
    }
    if (defined ($tainted_options->{ignore_regex})) {
        $new_options->{ignore_regex} = $tainted_options->{ignore_regex};
    }
    if (defined ($tainted_options->{default_time_zone})) {
        if ($tainted_options->{default_time_zone} =~ m!^([a-z0-9\/\_]+)!i) { $new_options->{default_time_zone} = $1; } else { croak "Bad default_time_zone"; }
    }
    if ($tainted_options->{date}) {
        if ($tainted_options->{date} =~ m!^(\d{8})$!i) { $new_options->{date} = $1; } else { croak "Bad date"; }
    }


    if (%$options) {
        # if options have changed, let the user know
        my %all_keys = map { $_ => 1 } (keys (%$options), keys (%$new_options));
        foreach (keys %all_keys) {
            if ($new_options->{$_} ne $options->{$_}) {
                print "Option $_ has changed from $options->{$_} to $new_options->{$_}\n";
            }
        }
    }
    $options = $new_options;

    print "options is ", Dumper($options)  if $options->{verbose};

    
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

      taskforest --run_wrapper=/foo/bin/run \
        --log_dir=/foo/logs \
        --job_dir=/foo/jobs \
        --family_dir=/foo/families

      OR

      taskforest --config_file=taskforest.cfg

      All jobs will run as the user who invoked taskforest.

      To get the status of all currently running and recently run jobs,
      enter the following command:

      status --collapse

For more detailed documentation, enter:

man TaskForest

or

perldoc TaskForest
 
^;
}

1
