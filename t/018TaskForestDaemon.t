# -*- perl -*-

use Test::More tests => 306;

use strict;
use warnings;
use Cwd;
use File::Copy;
use LWP::UserAgent;
use HTTP::Status;
use HTTP::Request::Common;
use TaskForest::LogDir;
use Data::Dumper;
use TaskForest::Test;

my $pid;
my $has_ssl_client = 0;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.19';

#     if (eval("require FOO")) {
#         $has_ssl_client = 1;
#     }
#     else {
#         $has_ssl_client = 0;
#         diag("The SSL client socket doesn't appear to be installed.");
#         diag("I won't try connecting to an SSL server, but will try");
#         diag("to connect to a non-SSL server instead");
#     }
}

#END { killTaskforestd(); }

setup_signals();

my $cwd = getcwd();
my $src_dir = "$cwd/t/family_archive";
my $dest_dir = "$cwd/t/families";
mkdir $dest_dir unless -d $dest_dir;

&TaskForest::Test::cleanup_files($dest_dir);

# clean up log  dir
$ENV{TF_LOG_DIR} = "$cwd/t/logs";
my $log_dir = &TaskForest::LogDir::getLogDir($ENV{TF_LOG_DIR});
&TaskForest::Test::cleanup_files($log_dir);


copy("$src_dir/IGNORE01", $dest_dir);
copy("$src_dir/IGNORE02", $dest_dir);
copy("$src_dir/IGNORE03.bak", $dest_dir);
copy("$src_dir/IGNORE04_HASH", "$dest_dir/#IGNORE04#");
copy("$src_dir/IGNORE05_TILDE", "$dest_dir/IGNORE05~");


#print "has_ssl_client = $has_ssl_client\n";


my $skip = 0;
{
    
    
    my $ua = LWP::UserAgent->new;
    my $ub = "http://127.0.0.1:1111/rest/1.0";
    my $req = HTTP::Request->new(GET => "$ub/jobList.html");
    $req->content('');
    my $resp = $ua->request($req);
    if($resp->code == RC_INTERNAL_SERVER_ERROR) {
        diag("");
        diag("**********************************************************************");
        diag("");
        diag("No web server was found at port 1111.  Skipping the rest of");
        diag("these tests.  If you want, you can start the web server and");
        diag("rerun 'make test'.");
        diag("");
        diag("To start the web server enter:");
        diag("");
        diag("perl -T -I lib ./blib/script/taskforestd --config_file=./taskforestd.test.cfg");
        diag("");
        diag("For more help, see http://www.taskforest.com");
        diag("");
        diag("**********************************************************************");
        diag("");
        $skip = 1;
    }
}



SKIP : {

skip "taskforestd web server not running", 306 if $skip;
my $user_agent = LWP::UserAgent->new;
$user_agent->agent("MyApp/0.1 ");
my $uri_base = "http://127.0.0.1:1111/rest/1.0";

# Create a request
my $request = HTTP::Request->new(GET => "$uri_base/jobList.html"); ; $request->authorization_basic('test', 'test'); 
$request->content('');

# Pass request to the user agent and get a response back
my $response = $user_agent->request($request);

# Check the outcome of the response
ok($response->code == RC_OK, "Can read jobList.html");

# check GET
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/jobs.html/J1");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Can read job J1");

# check ifModified
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/jobs.html/J1");
$request->headers->if_modified_since($response->headers->last_modified);
$response = $user_agent->request($request);
ok($response->code == RC_NOT_MODIFIED, "Not Modified");

# check ifNoneMatch
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/jobs.html/J1");
$request->headers->header("if-none-match" => $response->headers->header("ETag"));
$response = $user_agent->request($request);
ok($response->code == RC_NOT_MODIFIED, "Not Modified due to ETag");

# check ifModified
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/jobs.html/J1");
$request->headers->if_modified_since($response->headers->last_modified - 10);
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Has been Modified since 10 seconds before last modified");

# check Not Found
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/jobs.html/aaaaaJ1");
$response = $user_agent->request($request);
ok($response->code == RC_NOT_FOUND, "File not found (correctly)");




# check HEAD
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/jobs.html/J1");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Can call HEAD on job J1");

# check ifModified
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/jobs.html/J1");
$request->headers->if_modified_since($response->headers->last_modified);
$response = $user_agent->request($request);
ok($response->code == RC_NOT_MODIFIED, "HEAD: Not Modified");

# check ifNoneMatch
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/jobs.html/J1");
$request->headers->header("if-none-match" => $response->headers->header("ETag"));
$response = $user_agent->request($request);
ok($response->code == RC_NOT_MODIFIED, "HEAD: Not Modified due to ETag");

# check ifModified
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/jobs.html/J1");
$request->headers->if_modified_since($response->headers->last_modified - 10);
$response = $user_agent->request($request);
ok($response->code == RC_OK, "HEAD: Has been Modified since 10 seconds before last modified");

# check Not Found
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/jobs.html/aaaaaJ1");
$response = $user_agent->request($request);
ok($response->code == RC_NOT_FOUND, "HEAD: File not found (correctly)");


# check POST
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("POST");
$request->uri("$uri_base/jobs.html/J1");
$response = $user_agent->request($request);
ok($response->code == RC_METHOD_NOT_ALLOWED, "Jobs resource does note allow post");




# check PUT UPDATE

$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("PUT");
$request->uri("$uri_base/jobs.html/J1");
$request->content(join("\n",
                       "#!/bin/sh",
                       "",
                       "# 2",
                       "exit 0",
                       ""));
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT Update has worked");


# check PUT CREATE
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("PUT");
$request->uri("$uri_base/jobs.html/JNEW");
$request->content(join("\n",
                       "#!/bin/sh",
                       "",
                       "# This is a new job",
                       "exit 0",
                       ""));
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT NEW has worked");


# check PUT CREATE
unlink ("t/jobs/JNEW");
ok(! -e "t/jobs/JNEW",  "JNEW deleted");
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("PUT");
$request->uri("$uri_base/jobs.html/JNEW");
$request->content(join("\n",
                       "#!/bin/sh",
                       "",
                       "# This is a new job",
                       "exit 0",
                       ""));
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT NEW has worked");
ok(-e "t/jobs/JNEW",  "PUT NEW created the file");



# check overloaded post
$request = POST  "$uri_base/jobs.html/JNEW", [ _method => "PUT", file_contents => join("\n",
                                                                                       "#!/bin/sh",
                                                                                       "",
                                                                                       "# POST OVERLOADED modified new",
                                                                                       "exit 0",
                                                                                       "")]; ; $request->authorization_basic('test', 'test'); 
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Overloaded POST has worked");



# check PUT idempotence
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("PUT");
$request->uri("$uri_base/jobs.html/JNEW");
$request->content(join("\n",
                       "#!/bin/sh",
                       "",
                       "# This is a new job idempotent",
                       "exit 0",
                       ""));
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT idempotent 1 has worked");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT idempotent 2 has worked");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT idempotent 3 has worked");



# check DELETE
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("DELETE");
$request->uri("$uri_base/jobs.html/JNEW");
$response = $user_agent->request($request);
ok($response->code == RC_NO_CONTENT, "DELETE has worked");
ok(!-e "t/jobs/JNEW", "DELETE actually deleted the file");





# check families
$request = HTTP::Request->new(GET => "$uri_base/familyList.html"); ; $request->authorization_basic('test', 'test'); 
$request->content('');

# Pass request to the user agent and get a response back
$response = $user_agent->request($request);

# Check the outcome of the response
ok($response->code == RC_OK, "Can read familyList.html");

# check GET
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/families.html/IGNORE01");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Can read job J1");

# check ifModified
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/families.html/IGNORE01");
$request->headers->if_modified_since($response->headers->last_modified);
$response = $user_agent->request($request);
ok($response->code == RC_NOT_MODIFIED, "Not Modified");

# check ifNoneMatch
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/families.html/IGNORE01");
$request->headers->header("if-none-match" => $response->headers->header("ETag"));
$response = $user_agent->request($request);
ok($response->code == RC_NOT_MODIFIED, "Not Modified due to ETag");

# check ifModified
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/families.html/IGNORE01");
$request->headers->if_modified_since($response->headers->last_modified - 10);
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Has been Modified since 10 seconds before last modified");

# check Not Found
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/families.html/aaaaaIGNORE01");
$response = $user_agent->request($request);
ok($response->code == RC_NOT_FOUND, "File not found (correctly)");




# check HEAD
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/families.html/IGNORE01");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Can call HEAD on family IGNORE01");

# check ifModified
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/families.html/IGNORE01");
$request->headers->if_modified_since($response->headers->last_modified);
$response = $user_agent->request($request);
ok($response->code == RC_NOT_MODIFIED, "HEAD: Not Modified");

# check ifNoneMatch
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/families.html/IGNORE01");
$request->headers->header("if-none-match" => $response->headers->header("ETag"));
$response = $user_agent->request($request);
ok($response->code == RC_NOT_MODIFIED, "HEAD: Not Modified due to ETag");

# check ifModified
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/families.html/IGNORE01");
$request->headers->if_modified_since($response->headers->last_modified - 10);
$response = $user_agent->request($request);
ok($response->code == RC_OK, "HEAD: Has been Modified since 10 seconds before last modified");

# check Not Found
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("HEAD");
$request->uri("$uri_base/families.html/aaaaaIGNORE01");
$response = $user_agent->request($request);
ok($response->code == RC_NOT_FOUND, "HEAD: File not found (correctly)");


# check POST
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("POST");
$request->uri("$uri_base/families.html/IGNORE01");
$response = $user_agent->request($request);
ok($response->code == RC_METHOD_NOT_ALLOWED, "Families resource does note allow post");




# check PUT UPDATE

$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("PUT");
$request->uri("$uri_base/families.html/IGNORE01");
$request->content(join("\n",
                       "start => '00:00', tz => 'America/Chicago', days => 'Mon,Tue,Wed,Thu,Fri,Sat,Sun'",
                       "",
                       "J1()",
                       "# Foo foo bar bar",
                       ""));
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT Update has worked");


# check PUT CREATE
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("PUT");
$request->uri("$uri_base/families.html/IGNORENEW");
$request->content(join("\n",
                       "#!/bin/sh",
                       "",
                       "# This is a new job",
                       "exit 0",
                       ""));
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT NEW has worked");


# check PUT CREATE
unlink ("t/families/IGNORENEW");
ok(! -e "t/families/IGNORENEW",  "IGNORENEW deleted");
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("PUT");
$request->uri("$uri_base/families.html/IGNORENEW");
$request->content(join("\n",
                       "#!/bin/sh",
                       "",
                       "# This is a new job",
                       "exit 0",
                       ""));
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT NEW has worked");
ok(-e "t/families/IGNORENEW",  "PUT NEW created the file");



# check overloaded post
$request = POST  "$uri_base/families.html/IGNORENEW", [ _method => "PUT", file_contents => join("\n",
                                                                                       "#!/bin/sh",
                                                                                       "",
                                                                                       "# POST OVERLOADED modified new",
                                                                                       "exit 0",
                                                                                       "")]; ; $request->authorization_basic('test', 'test'); 
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Overloaded POST has worked");



# check PUT idempotence
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("PUT");
$request->uri("$uri_base/families.html/IGNORENEW");
$request->content(join("\n",
                       "#!/bin/sh",
                       "",
                       "# This is a new job idempotent",
                       "exit 0",
                       ""));
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT idempotent 1 has worked");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT idempotent 2 has worked");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "PUT idempotent 3 has worked");



# check DELETE
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("DELETE");
$request->uri("$uri_base/families.html/IGNORENEW");
$response = $user_agent->request($request);
ok($response->code == RC_NO_CONTENT, "DELETE has worked");
ok(!-e "t/families/IGNORENEW", "DELETE actually deleted the file");


# now check status
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/status.html");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Status Invoked 1");
&TaskForest::Test::checkStatus($response->content, [
                ["IGNORE01", "J1", "Ready", "-", "America/Chicago", "00:00", "--:--", "--:--"],
                ["IGNORE02", "J2", "Ready", "-", "America/Chicago", "00:00", "--:--", "--:--"],
            ]);
             


# now run J1
&TaskForest::Test::fakeRun($log_dir, "IGNORE01", 'J1', 0);



# now mark J1 failed
$request = POST  "$uri_base/request.html", [
    family => 'IGNORE01',
    job => 'J1',
    status => 'Failure',
    submit => 'Mark'
    ]; ; $request->authorization_basic('test', 'test'); 
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Marked J1 Failed");



# now rerun J1
$request = POST  "$uri_base/request.html", [
    family => 'IGNORE01',
    job => 'J1',
    submit => 'Rerun'
    ]; ; $request->authorization_basic('test', 'test'); 
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Rerun request for J1 sent");


# now check status
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/status.html");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Status Invoked 1");
&TaskForest::Test::checkStatus($response->content, [
                ["IGNORE01", "J1--Orig_1--", "Failure", "0", "America/Chicago", "00:00", "23:20", "23:20"],
                ["IGNORE01", "J1",           "Ready",   "-", "America/Chicago", "00:00", "--:--", "--:--"],
                ["IGNORE02", "J2",           "Ready",   "-", "America/Chicago", "00:00", "--:--", "--:--"],
            ]);


# now test cascade and dependents only
&TaskForest::Test::cleanup_files($dest_dir);
&TaskForest::Test::cleanup_files($log_dir);
copy("$src_dir/SMALL_CASCADE", $dest_dir);

# now run Jobs
&TaskForest::Test::fakeRun($log_dir, "SMALL_CASCADE", 'J2', 0);
&TaskForest::Test::fakeRun($log_dir, "SMALL_CASCADE", 'J7', 0);
&TaskForest::Test::fakeRun($log_dir, "SMALL_CASCADE", 'J8', 0);

# now check status
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/status.html");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Status Invoked 4");
&TaskForest::Test::checkStatus($response->content, [
                ["SMALL_CASCADE", "J2", "Success", "0", "America/Chicago", "00:00", "23:20", "23:20"],
                ["SMALL_CASCADE", "J7", "Success", "0", "America/Chicago", "00:00", "23:20", "23:20"],
                ["SMALL_CASCADE", "J8", "Success", "0", "America/Chicago", "00:00", "23:20", "23:20"],
            ]);


    
# now rerun J2
$request = POST  "$uri_base/request.html", [ 
    family => 'SMALL_CASCADE',
    job => 'J2',
    submit => 'Rerun',
    options => 'cascade',
    ]; ; $request->authorization_basic('test', 'test'); 
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Rerun request sent");



# now check status
$request = HTTP::Request->new; ; $request->authorization_basic('test', 'test'); 
$request->method("GET");
$request->uri("$uri_base/status.html");
$response = $user_agent->request($request);
ok($response->code == RC_OK, "Status Invoked");
&TaskForest::Test::checkStatus($response->content, [
                ["SMALL_CASCADE", "J2--Orig_1--", "Success", "0", "America/Chicago", "00:00", "23:20", "23:20"],
                ["SMALL_CASCADE", "J2",           "Ready",   "-", "America/Chicago", "00:00", "--:--", "--:--"],
                ["SMALL_CASCADE", "J7--Orig_1--", "Success", "0", "America/Chicago", "00:00", "23:20", "23:20"],
                ["SMALL_CASCADE", "J7",           "Waiting", "-", "America/Chicago", "00:00", "--:--", "--:--"],
                ["SMALL_CASCADE", "J8--Orig_1--", "Success", "0", "America/Chicago", "00:00", "23:20", "23:20"],
                ["SMALL_CASCADE", "J8",           "Waiting", "-", "America/Chicago", "00:00", "--:--", "--:--"],
            ]);


# now test BAD request
 $request = POST  "$uri_base/request.html", [ 
     family => 'SMALL_CASCADE',
     job => 'J2',
     submit => 'JUNK',
     options => 'cascade',
     ]; ; $request->authorization_basic('test', 'test'); 
$response = $user_agent->request($request);
ok($response->code == RC_BAD_REQUEST, "Bad Request for Request handled.");


}




#killTaskforestd();


sub killTaskforestd {
    if (open (F, "taskforestd.pid")) {
        $pid = <F>;
        close F;
        chomp $pid;
        print "Killing server with pid $pid\n";
        kill "INT", $pid;
    }
}


sub setup_signals {             
    setpgrp;                      # I *am* the leader
    $SIG{HUP} = $SIG{INT} = $SIG{TERM} = sub {
        my $sig = shift;
        # remove pid file
        $SIG{$sig} = 'IGNORE';
        kill $sig, 0;               # death to all-comers

        exit 1;
    };
}
