################################################################################
#
# File:    LogDir
# Date:    $Date: 2008-03-27 18:23:10 -0500 (Thu, 27 Mar 2008) $
# Version: $Revision: 86 $
#
# This is a simple package that provides a location for the getLogDir
# function that's used in a few places
#
################################################################################
package TaskForest::LogDir;
use strict;
use warnings;

my $log_dir_cached;

################################################################################
#
# Name      : getLogDir
# Usage     : my $log_dir = TaskForest::LogDir::getLogDir($root)
# Purpose   : This method creates a dated subdirectory of its first
#             parameter, if that directory doesn't already exist.  
# Returns   : The dated directory
# Argument  : $root - the parent directory of the dated directory
# Throws    : "mkdir $log_dir failed" if the log directory cannot be
#             created 
#
################################################################################
#
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
            die "mkdir $log_dir failed in LogDir::getLogDir!\n";
        }
    }
    $log_dir_cached = $log_dir;
    return $log_dir;
}


1;
