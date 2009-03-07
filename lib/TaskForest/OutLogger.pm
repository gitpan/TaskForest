# -*-perl-*-

################################################################################
#
# $Id: OutLogger.pm 137 2009-03-07 04:47:48Z aijaz $
#
################################################################################

=head1 NAME

TaskForest::OutLogger - Functions related to logging to stdout

=head1 DOCUMENTATION

This is a class that is used to tie prints to STDOUT to $log->info();
See Logger::Log4perl for more details. 

=cut


package TaskForest::OutLogger;


use strict;
use warnings;
use TaskForest::Logs;
use Log::Log4perl;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.19';
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

