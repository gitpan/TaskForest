
use 5.008003;

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'TaskForest',
    VERSION_FROM => 'lib/TaskForest.pm', # finds \$VERSION
    AUTHOR       => 'Aijaz A. Ansari (v-cpan@enoor.com)',
    ABSTRACT     => 'Simple, powerful task scheduler',
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
                     'DateTime' => 0,
                    },
    INSTALLSITEBIN => "bin",
    INSTALLSCRIPT => "bin",
    INSTALLBIN => "bin",
    EXE_FILES => ["run", "taskforest", "status", "rerun", "mark"],
);


#FULL_PERL!
#my $path_to_perl = prompt("Please enter the path to your perl: ", "/usr/local/bin/perl");
