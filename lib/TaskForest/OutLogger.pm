# -*-perl-*-

################################################################################
#
# $Id: OutLogger.pm 38 2008-05-29 03:26:09Z aijaz $
#
################################################################################

=head1 NAME

TaskForest::OutLogger - Functions related to logging to stdout

=head1 DOCUMENTATION

More documentation will be made available in release 1.12

=cut


package TaskForest::OutLogger;


use strict;
use warnings;
use TaskForest::Logs;
use Log::Log4perl;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.11';
}

sub TIEHANDLE {
    my $class = shift;
    bless { log => $TaskForest::Logs::log } , $class;
}

sub PRINT {
    my $self = shift;
    $Log::Log4perl::caller_depth++;
    $self->{log}->info(@_);
    $Log::Log4perl::caller_depth--;
}

1;

