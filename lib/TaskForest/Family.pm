################################################################################
#
# File:    Family
# Date:    $Date: 2008-04-04 23:16:41 -0500 (Fri, 04 Apr 2008) $
# Version: $Revision: 117 $
#
################################################################################


=head1 NAME

TaskForest::Family - A collection of jobs

=head1 SYNOPSIS

 use TaskForest::Family;

 my $family = TaskForest::Family->new(name => 'Foo');
 # the associated job dependencies are read within new();

 $family->getCurrent();
 # get the status of all jobs, what's failed, etc.

 $family->cycle();
 # runs any jobs that are ready to be run

 $family->display();
 # print to stdout a list of all jobs in the family
 # and their statuses

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

A family is a group of jobs that share the following
characteristics:

=over

=item *

They all start on or after a common time known as the family start time.

=item *

They run only on the days specified in the family file.

=item *

They can be dependent on each other.  These dependencies are
represented by the location of jobs with respect to each other in
the family file.

=back

For more information about jobs, please look at the documentation for
the TaskForest class.

=head1 ATTRIBUTES

The following are attributes of objects of the family class:

=over 2

=item name

The name is the same as the name of the config file that contains the
job dependency information.

=item start

The family start time in 'HH:MM' format using the 24-hour clock. e.g.:
'17:30' for 5:30 p.m.

=item tz

The time zone with which the family start time is to be interpreted.

=item days

An array reference of days of the week on which this family's jobs may
run.  Valid days are 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' and  'Sun'.
Anything else will be ignored.

=item options

A hash reference that contains the values of the options retrieved from
the command line or the environment,

=item jobs

A hash reference of all the jobs that are members of this family.  The
keys of this hash are the names of the jobs.  The names of the jobs are in
the family configuration file and they're the same as the filenames of the
jobs on disk.

=item current

A boolean that is set to true after all the details of the family's jobs
are read from status files in the log directory.  This boolean is set to
false when an attempt is made to run any jobs, and when the family config
file is first read (before getCurrent() is called).

=item ready_jobs

A temporary hash reference of jobs that are ready to be run - jobs whose
dependencies have been met.

=item dependencies

A hash reference of dependencies of all jobs (things that the jobs depend
ON).  The keys of this hash are the job names.  The values are array
references.  Each array reference can contain 1 or more references to
objects of type TaskForest::Job or TaskForest::TimeDependency.

All jobs have at least one dependency - a TimeDependency that's set to the
start time of the Family.  In other words, after the start time of the
Family passes, the check() method of the TimeDependency will return 1.
Before that, it will return 0.

=item time_dependencies

For convenience, all time dependencies encountered in this family
(including that of the family start time) are saved in this array
reference.  The other types of time dependencies are those that apply to
individual jobs.

=item family_time_dependency

This is the TaskForest::TimeDependency that refers to the family start
time.

=item year, mon, mday and wday

These attributes refer to the current day.  They're saved within the
Family object so that we don't have to call localtime over and over again.
I really should have this cached this somewhere else.  Oh, well.

=item filehandle

The readFromFile function was *really* long, so I refactored it into
smaller functions.  Since at least two of the functions read from the
file, I saved the file handle within the object.

=item current_dependency, last_dependency

These are temporary attributes that builds dependency lists while parsing
the file.  

=back    

=head1 METHODS

=cut    

package TaskForest::Family;

use strict;
use warnings;
use TaskForest::Job qw ();
use Data::Dumper;
use TaskForest::TimeDependency;
use TaskForest::Options;
use TaskForest::LogDir;
use English '-no_match_vars';
use FileHandle;
use Carp;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.06';
}

# ------------------------------------------------------------------------------
=pod

=over 4

=item new()

 Usage     : my $family = TaskForest::Family->new();
 Purpose   : The Family constructor is passed the family name.  It
             uses this name along with the location of the family
             directory to find the family configuration file and
             reads the file.  The family object is configured with
             the data read in from the file.
 Returns   : Self
 Argument  : A hash that has the properties of he family.  Of these,
             the only required one is the 'name' property.
 Throws    : "No family name specified" if the name property is
              blank.  

=back

=cut

# ------------------------------------------------------------------------------
sub new {
    my $arg = shift;
    my $class = (ref $arg) || $arg;

    my $self = {
        name   => '',
        start  => '',
        tz     => 'America/Chicago',        # default America/Chicago
        days   => {},
    };

    my %args = @_;
    
    foreach my $key (keys %args) {
        $self->{$key} = $args{$key};
    }

    croak "No family name specified" unless $self->{name};
    bless $self, $class;

    $self->{options} = &TaskForest::Options::getOptions();
    
    $self->readFromFile();

    return $self;
}


# ------------------------------------------------------------------------------
=pod

=over 4

=item display()

 Usage     : $family->display()
 Purpose   : This method displays the status of all jobs in all
             families that are scheduled to run today. 
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub display {
    my $self = shift;

    my $display_hash = { all_jobs => [], Success  => [], Failure  => [], Ready  => [], Waiting  => [],  };

    my $max_len_name = 0;
    my $max_len_tz = 0;
    
    foreach my $job_name (sort
                          { $self->{jobs}->{$a}->{start} cmp $self->{jobs}->{$b}->{start} }
                          (keys (%{$self->{jobs}}))) {
        my $l = length($job_name);
        $max_len_name = $l if ($l > $max_len_name);
        my $job = $self->{jobs}->{$job_name};
        $l = length($job->{tz});
        $max_len_tz = $l if ($l > $max_len_tz);
        
        # dont show pending repeat jobs
        # next if ($job->{status} eq 'Waiting' and $job->{name} =~ /--Repeat/);
        # TODO: make this an option?
        
        my $job_hash = {};
        foreach my $k (keys %$job) { $job_hash->{$k} = $job->{$k}; }
        push (@{$display_hash->{all_jobs}}, $job_hash);
        push (@{$display_hash->{$job_hash->{status}}}, $job_hash);
    }
    foreach my $job (@{$display_hash->{Ready}}, @{$display_hash->{Waiting}}) {
        $job->{actual_start} = $job->{stop} = "--:--";
        $job->{rc} = '-';
    }

    foreach my $job (@{$display_hash->{Success}}, @{$display_hash->{Failure}}) {
        my $dt = DateTime->from_epoch( epoch => $job->{actual_start} );
        $dt->set_time_zone($job->{tz});
        $job->{actual_start} = sprintf("%02d:%02d", $dt->hour, $dt->minute);

        if ($job->{stop}) {
            $dt = DateTime->from_epoch( epoch => $job->{stop} );
            $dt->set_time_zone($job->{tz});
            $job->{stop} = sprintf("%02d:%02d", $dt->hour, $dt->minute);
        }
        else {
            $job->{stop} = '--:--';
            $job->{rc} = '-';
        }
    }

    $max_len_name += length($self->{name}) + 2;
    my $format = "%-${max_len_name}s   %-7s   %6s   %-${max_len_tz}s   %-5s   %-6s  %-5s\n";
    printf($format, '', '', 'Return', 'Time', 'Sched', 'Actual', 'Stop');
    printf($format, 'Job', 'Status', 'Code', 'Zone', 'Start', 'Start', 'Time');
    print "\n";
    foreach my $job (@{$display_hash->{all_jobs}}) {
        printf($format,
               "$self->{name}::$job->{name}",
               $job->{status},
               $job->{rc},
               $job->{tz},
               $job->{start},
               $job->{actual_start},
               $job->{stop});
    }

}
    

# ------------------------------------------------------------------------------
=pod

=over 4

=item getCurrent()

 Usage     : $family->getCurrent()
 Purpose   : This method reads all the semaphore files in the log
             directory and gets the current status of the entire
             family.  Each run job can have succeeded or failed.  As
             a result of this, other jobs may be Ready to be run.  If
             a job's dependencies have not yet been met, it is said
             to be in the Waiting state.  Once a family is current,
             the only thing that makes it 'uncurrent' is if any jobs
             are run, or if its configuration file changes.
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub getCurrent {
    my $self = shift;

    if ($self->{current}) {
        # nothing to do, really
        return;
    }

    # Get the status of all jobs, depending on the presence of job
    # semaphore files
    # 
    $self->updateJobStatuses();

    # Check to see if any of the time dependencies in this family have
    # been met.  A time dependency has been met if 'now' >= the time
    # dependency.
    #
    $self->checkAllTimeDependencies();

    # Get a list of all jobs whose status is 'Waiting'
    #
    my $waiting_jobs = $self->getAllWaitingJobs();
    print "waiting: ", Dumper($waiting_jobs) if $self->{options}->{verbose};

    # Construct a list of all ready jobs - these are jobs for which
    # all dependencies have been met
    #
    $self->{ready_jobs} = {};
    foreach my $job (values %$waiting_jobs) {
        # dependencies for each job
        #
        my $dependencies = $self->{dependencies}->{$job->{name}};
        my $ready = 1;

        foreach my $dep (@$dependencies) {
            if ($dep->check() == 0) {
                $ready = 0;
                last;
            }
        }

        if ($ready) {
            # set the status of the job to be ready
            $self->{ready_jobs}->{$job->{name}} = $job;
            $job->{status} = 'Ready';
        }
    }

    $self->{current} = 1;
    print "ready: ", Dumper($self->{ready_jobs}) if $self->{options}->{verbose};
}


# ------------------------------------------------------------------------------
=pod

=over 4

=item cycle()

 Usage     : $family->cycle()
 Purpose   : This is the main method that is invoked once in every
             loop, to run any jobs that are in a Ready state.  It
             gets the current status of the family and runs any jobs
             that are in the Ready state.
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub cycle {
    my $self = shift;

    $self->getCurrent();
    $self->runReadyJobs();
}



# ------------------------------------------------------------------------------
=pod

=over 4

=item updateJobStatuses()

 Usage     : $family->updateJobStatuses()
 Purpose   : This method looks at all the semaphore files in the
             current day's log directory and updates job statuses
             based on those semaphore files. 
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub updateJobStatuses {
    my $self = shift;

    my $log_dir = &TaskForest::LogDir::getLogDir($self->{options}->{log_dir});

    # keep in mind that semaphore files are in the form F.J.[01] where
    # F is the family name, J is a job name and 0 means success, and 1
    # failure
    #
    my $glob_string = "$log_dir/$self->{name}.*.[01]";

    my @files = glob($glob_string);
    my %valid_fields = (
        actual_start => 1,
        pid => 1,
        stop => 1,
        rc => 1,
        );
    

    foreach my $file (sort @files) { # the sort ensures that 1 overrides 0
        my ($job_name, $status) = $file =~ /$log_dir\/$self->{name}\.([^\.]+)\.([01])/;

        # when a job is rerun the .[01] file is moved to .r[01] file
        if ($status == 1) {
            $self->{jobs}->{$job_name}->{status} = 'Failure';
        }
        else {
            $self->{jobs}->{$job_name}->{status} = 'Success';
        }
        # read the return code
        #
        open(F, $file) || croak "cannot open $file to read rc";
        $_ = <F>;
        chomp;
        $self->{jobs}->{$job_name}->{rc} = $_;
        close F;

        # read the pid file
        substr($file, -1, 1) = 'pid';
        open(F, $file) || croak "cannot open $file to read job data";
        while (<F>) { 
            chomp;
            my ($k, $v) = /([^:]+): (.*)/;
            $v =~ s/[^a-z0-9_ ,.\-]/_/ig;
            if ($valid_fields{$k}) {
                $self->{jobs}->{$job_name}->{$k} = $v;
            }
        }
        close F;
    }
}
        
        

# ------------------------------------------------------------------------------
=pod

=over 4

=item runReadyJobs()

 Usage     : $family->runReadyJobs()
 Purpose   : This method uses the fork and exec model to run all jobs
             currently in the Ready state.  The script that is
             actually exec'ed is the run wrapper.  The wrapper takes
             a whole bunch of arguments, some of which can be derived
             by others.  The intent is to make it flexible and make
             it easy for others to write custom wrappers.  The code
             that's executed in the child process before the exec is
             rather paranoid and is taken from perldoc perlsec.
 Returns   : Nothing
 Argument  : None
 Throws    : "Can't drop privileges" if the userids cannot be
             changed

=back

=cut

# ------------------------------------------------------------------------------
sub runReadyJobs {
    my $self = shift;
    $self->{current} = 0; # no longer current.  A reread of log dirs is necessary
    my $wrapper = $self->{options}->{run_wrapper};
    my $log_dir = &TaskForest::LogDir::getLogDir($self->{options}->{log_dir});
    
    foreach my $job (values %{$self->{ready_jobs}}) { 
        my $pid;
        if ($pid = fork) {
            # parent
            print "Forked child process $job->{name} $pid\n";
            $job->{status} = 'Running';
        } else {
            #child - this code comes from perldoc perlsec
            croak "cannot fork: $!" unless defined $pid;

            my @temp     = ($EUID, $EGID);
            my $orig_uid = $UID;
            my $orig_gid = $GID;
            $EUID = $UID;
            $EGID = $GID;
            
            # Drop privileges
            #
            $UID  = $orig_uid;
            $GID  = $orig_gid;
            
            # Make sure privs are really gone
            #
            ($EUID, $EGID) = @temp;
            croak "Can't drop privileges" unless $UID == $EUID  && $GID eq $EGID;
            $ENV{PATH} = "/bin:/usr/bin"; # Minimal PATH.
            $ENV{CDPATH} = ""; # We don't need this.
            
            # Consider sanitizing the environment even more.
            
            my $job_file_name = $job->{name};
            $job_file_name =~ s/--Repeat.*//;
            
            exec("$wrapper",
                 "$self->{name}",
                 "$job->{name}",
                 "$job_file_name",
                 "$log_dir",
                 "$self->{options}->{job_dir}",
                 "$log_dir/$self->{name}.$job->{name}.pid",
                 "$log_dir/$self->{name}.$job->{name}.0",
                 "$log_dir/$self->{name}.$job->{name}.1",
                ) or croak "Can't exec: $!\n";
        }
    }
        
}

    

# ------------------------------------------------------------------------------
=pod

=over 4

=item checkAllTimeDependencies()

 Usage     : $family->checkAllTimeDependencies()
 Purpose   : Runs td->check() on all time dependencies, to see
             whether they have been met or not
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub checkAllTimeDependencies {
    my $self = shift;

    foreach my $td (@{$self->{time_dependencies}}) {
        $td->check();
    }
}

# ------------------------------------------------------------------------------
=pod

=over 4

=item getAllWaitingJobs()

 Usage     : $family->getAllWaitingJobs()
 Purpose   : This method gets a hash of all jobs that are currently
             in the Waiting state
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub getAllWaitingJobs {
    my $self = shift;

    my %waiting = map { $_->{name} => $_ } grep {$_->{status} eq 'Waiting'} values(%{$self->{jobs}});

    return \%waiting;
}


# ------------------------------------------------------------------------------
=pod

=over 4

=item readFromFile()

 Usage     : $family->readFromFile
 Purpose   : This is the most crucial method of the application.  It
             reads the Family configuration file and constructs a
             data structure that represents all the configuration
             parameters of the family.
 Returns   : Nothing
 Argument  : None
 Throws    : "Can't read dir/file" if the config file cannot be read
             "No start time specified for Family",
             "No time zone specified for Family",
             "No run days specified for Family",
                if any of the 3 required headers are not present in
                the file
             Generic croak if the data cannot be extracted after an
             eval.

=back

=cut

# ------------------------------------------------------------------------------
sub readFromFile {
    my $self = shift;

    $self->_initializeDataStructures();

    my $file = $self->{name};
    my $dir = $self->{options}->{family_dir};
    $self->{file_handle} = new FileHandle;
    $self->{file_handle}->open("<$dir/$file") || croak "cant read $dir/$file";

    my $ok_to_run = $self->_parseHeaderLine();
    return unless $ok_to_run;
    

    my $sections = $self->_getSections();     # get concurrent sections
    return unless @$sections;                 # the file is either blank, or does not need to run today

    foreach my $section (@$sections) {
        my @lines = split(/[\r\n]/, $section);    # lines in the section
        
        # Create a one-element array of dependencies.  This is the
        # default dependency list for all jobs as they're first
        # encountered. 
        #
        $self->{last_dependency} = [ $self->{family_time_dependency} ];
        foreach my $line (@lines) {
            $self->_parseLine($line);
        }
    }

}


# ------------------------------------------------------------------------------
=pod

=over 4

=item okToRunToday()

 Usage     : $family->okToRunToday
 Purpose   : This method checks whether today is in the list of days
             of the week that this family is eligible to run
 Returns   : 1 if it is, 0 if it's not.
 Argument  : $wday - the day of the week today
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub okToRunToday {
    my ($self, $wday) = @_;

    my @days = qw (Sun Mon Tue Wed Thu Fri Sat);
    my $today = $days[$wday];

    if ($self->{days}->{$today}) {
        return 1;
    }
    else {
        return 0;
    }
}


# ------------------------------------------------------------------------------
=pod

=over 4

=item _initializeDataStrauctures()

 Usage     : $self->_intializeDataStructures
 Purpose   : Used in readFrom file, before a file is opened for reading
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub _initializeDataStructures {
    my $self = shift;
    
    $self->{dependencies} = {};
    $self->{jobs} = {};
    $self->{time_dependencies} = [];

    # once you reread a family's config file, it is no longer current
    #
    $self->{current} = 0;

    # get current time
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time); $year += 1900; $mon ++;
    ($self->{year}, $self->{mon}, $self->{mday}, $self->{wday}) = ($year, $mon, $mday, $wday);

    
}



# ------------------------------------------------------------------------------
=pod

=over 4

=item _getSections()

 Usage     : $self->_getSections
 Purpose   : Read concurrent sections from the family file 
 Returns   : A list of sections, or () if the file is empty
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub _getSections {
    my $self = shift;
    my $fh = $self->{file_handle};   
   
    # PARSE THE FILE HERE
    my @sections = split(/^ *-+ *[\r\n]+/m,             # split on a line of dashes
                         (join '',                      # convert back to a string
                          grep(/\S/,                    # get rid of blank lines
                               (map {s/\#.*//; $_; }    # get rid of comments
                                $fh->getlines()))));             # all lines as a list
    
    $fh->close();

    return \@sections;
}


# ------------------------------------------------------------------------------
=pod

=over 4

=item _parseHeaderLine()

 Usage     : $self->_parseHeaderLine()
 Purpose   : Read the first non-empty line from the family file.
             If this family is not scheduled to run today, then just
             close the file and return 0.  This means that you
             could change the days in the header file in the middle
             of the day, and add today to the list of valid
             days. This would cause the family to now become
             eligible to run today, when earlier in the  day it was
             not. 
 Returns   : 1 if the family is to run today, 0 otherwise.
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub _parseHeaderLine {
    my $self = shift;
    my $fh = $self->{file_handle};
    while (<$fh>) {
        chomp;
        last if /\S/;  # get first non-blank line
    }

    s/\s//g;           # get rid of spaces

    # make sure all the data we expect in the header is available
    #
    my $args = '';
    my $file = $self->{name};
    if (/(start=>['"]\d+:\d+['"])/)      { $args .= "$1,"; } else { croak "No start time specified for Family $file"; }
    if (/(days=>['"][a-zA-Z0-9,]+['"])/) { $args .= "$1,"; } else { croak "No run days specified for Family $file"; }
    if (/(tz=>['"][a-zA-Z0-9\/]+['"])/)  { $args .= "$1,"; } else { croak "No time zone specified for Family $file"; }
             
    my %args = eval($args);

    $self->{start} = $args{start};          # set the start time
    my @days = split(/,/, $args{days});
    foreach my $day (@days) {
        $self->{days}->{$day} = 1;          # valid to run on these days
    }

    if ($self->okToRunToday($self->{wday}) == 0) {  # nothing to do
        $fh->close();
        return 0;
    }

    # create main dependency - every job has at least one dependency:
    # a time dependency on the start time of the family.   
    #
    my %td_args = ( start => $self->{start} );
    $td_args{tz} = $self->{tz};                  # for now, this is a required field
    $self->{family_time_dependency} = TaskForest::TimeDependency->new(%td_args);
    push (@{$self->{time_dependencies}}, $self->{family_time_dependency});

    return 1;
}

# ------------------------------------------------------------------------------
=pod

=over 4

=item _parseLine()

 Usage     : $self->_parseLine($line)
 Purpose   : Get a list of all jobs on the line and parse them,
             creating the data structure.
             As we process each line, we add to each job's
             dependencies the dependencies in
             $self->{last_dependency}.  We also add each job to the
             list of 'current' dependencies.  When we're done parsing
             the line, we set 'last' to 'current', for the benefit of
             the next line.
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub _parseLine {
    my ($self, $line) = @_;

    $self->{current_dependency} = [];
    $line =~ s/\s//g;                    # get rid of spaces

    my @jobs = $line =~ /([a-z0-9_]+\([^\)]*\))/ig;  # parens may be empty

    foreach my $job (@jobs) {
        $self->_parseJob($job);

    }

    # set the list of dependencies for the next iteration in
    # the loop
    #
    $self->{last_dependency} = $self->{current_dependency};
}



# ------------------------------------------------------------------------------
=pod

=over 4

=item _parseJob()

 Usage     : $self->_parseJob($job)
 Purpose   : Parse the job definition, create additional dependencies
             if necessary, and create the job.  If it's a recurring
             job, then create a bunch of 'repeat' jobs that are not
             dependent on the original job's predecessors, but on
             time dependencies only.
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub _parseJob {
    my ($self, $job) = @_;
    
    my ($job_name, $args) = $job =~ /([a-z0-9_]+)(\([^\)]*\))/i;   

    my $job_object;
    if ($self->{jobs}->{$job_name}) {
        $job_object = $self->{jobs}->{$job_name};   # job already exists in this family
    }
    else {
        $job_object = TaskForest::Job->new(name => $job_name);  # create new job
        $self->{jobs}->{$job_name} = $job_object;
    }

    # Set dependencies.  A dependency can be a time dependency or another job
    #
    $self->{dependencies}->{$job_name} = [] unless $self->{dependencies}->{$job_name};
    foreach my $dep (@{$self->{last_dependency}}) {
        push (@{$self->{dependencies}->{$job_name}}, $dep);
    }
    
    if ($args =~ /^\(\S/) {  # We have additional dependencies
        my %args = eval ($args);
        $args{tz} = $self->{tz} unless $args{tz}; # time zone defaults to family time zone
        if ($args{start}) {                       # time dependency
            my $td = TaskForest::TimeDependency->new(start => $args{start}, tz => $args{tz});
            push (@{$self->{dependencies}->{$job_name}}, $td);
            push (@{$self->{time_dependencies}}, $td);
        }
        else {
            $args{start} = $self->{start};
        }

        ($job_object->{start} , $job_object->{tz}) = ($args{start}, $args{tz});
        
        if ($args{every} and $args{every} !~ /\D/) {
            $self->_createRecurringJobs($job_name, \%args);
        }
    }
    
    # push this job into the dependency array for the jobs in the next line
    #
    push (@{$self->{current_dependency}}, $job_object)

}    


# ------------------------------------------------------------------------------
=pod

=over 4

=item _createRecurringJobs()

 Usage     : $self->_createRecurringJobz($job_name, $args)
 Purpose   : If a job is a recurring job, create new jobs with a
             prefix of --Repeat_$n-- where $n specifies the
             cardinality of the repeat job.  The newly created jobs
             are *not* dependent on each other. They're only
             dependent on their start times. 
 Returns   : Nothing
 Argument  : None
 Throws    : Nothing

=back

=cut

# ------------------------------------------------------------------------------
sub _createRecurringJobs {
    my ($self, $job_name, $args) = @_;
    
    my $until = $args->{until};
    my ($until_mm, $until_hh);
    if ($until =~ /^(\d\d):(\d\d)$/) { $until_hh = $1; $until_mm = $2; }
    else {                             $until_hh = 23; $until_mm = 59; }

    # get an epoch value for the the until time
    #
    my $until_epoch = DateTime->new(year => $self->{year}, month => $self->{mon}, day => $self->{mday}, hour => $until_hh, minute => $until_mm, time_zone => $args->{tz})->epoch();

    # get a start time epoch value, defaulting to the family start time
    #
    my ($start_dt, $start_hh, $start_mm);
    $args->{start} = $self->{start} unless $args->{start};       # default start is famil start
    ($start_hh, $start_mm) = $args->{start} =~ /(\d\d):(\d\d)/;
    $start_dt = DateTime->new(year => $self->{year},  month => $self->{mon}, day => $self->{mday}, hour => $start_hh, minute => $start_mm, time_zone => $args->{tz});

    # create a duration value that's added in every loop
    #
    my $every_duration = DateTime::Duration->new(minutes => $args->{every});
    my $next_dt = $start_dt + $every_duration;
    my $next_epoch = $next_dt->epoch();
    my $next_n = 0;
    while ($next_epoch <= $until_epoch) {
        $next_n++;
        my $jn = "$job_name--Repeat_$next_n--";
        my $td = TaskForest::TimeDependency->new($next_dt);
        $self->{dependencies}->{$jn} = [$td];
        my $repeat_job_object = TaskForest::Job->new(name => $jn, tz=>$args->{tz}, start => $td->{start});
        $self->{jobs}->{$jn} = $repeat_job_object;

        $next_dt = $next_dt + $every_duration;
        $next_epoch = $next_dt->epoch();
    }
}


1;



    
    
