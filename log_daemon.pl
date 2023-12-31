#!/usr/bin/perl
#use strict;
use warnings;
use DBI;
use URI;
use English qw( -no_match_vars );
use Getopt::Long;
use Pod::Usage;
use POSIX qw(strftime);
use File::Basename;
use Data::Dumper;
use Storable qw( lock_store lock_retrieve );
use Data::Uniqid qw ( suniqid uniqid luniqid );
##################  Conexion a BD mySql y variables ####################
my $path = dirname(__FILE__);

my $logFile ="";  #log file url
my $envFile = $path."/.env";
my $stateDir =$path."/storage/logs";
my $cacheFile =$stateDir."/log.daemon.cache.db";
my $tmpLogDir = $stateDir."/loginfo/";
my $tmpLogFile = undef;
my $cache = {};
my $cacheLog ={};
my  $dbDriver= "mysql";
my  $dbHost = "127.0.0.1";
my  $database = "squidadmin";
my  $dbUser = "squidadmin";
my  $dbPass = "somepassword";
my $debug = 1;
# others may be options

# utility  to print messages on stderr 
sub logInfo {
    if($debug){
		my $msg = shift;
		print STDERR "$msg\n";
	}
}
logInfo( "Reading db config");
open (my $envFh, "<", $envFile) || die "could not open env file $envFile! $!";

while(<$envFh>) {
    my $line = $_ ;
	chomp;
	if (/\bDB_CONNECTION=\s*(mysql|pgsql)/){
		if( $1 eq "pgsql"){
			$dbDriver = "Pg";
		}
	}
	if (/\bDB_HOST=\s*(.*)/){
		$dbHost = $1;
	}	
	if (/\bDB_DATABASE=\s*(.*)/){
		$database = $1;
	}	    
	if (/\bDB_USERNAME=\s*(.*)/){
		$dbUser = $1;
	}	
	if (/\bDB_PASSWORD=\s*(.*)/){
		$dbPass = $1;
	}	
	#logInfo( $_);
}
close $envFh;

if (! -d $stateDir) {
	mkdir $stateDir;
}
if (! -d $tmpLogDir) {
	mkdir $tmpLogDir;
}


# DSN config
my $dsn = "DBI:$dbDriver:database=$database;host=$dbHost";
my $dbh;
my $sth;
eval {
    warn "Connecting dsn='$dsn', usuario='$dbUser', contra='...'";
    $dbh = DBI->connect($dsn, $dbUser, $dbPass, { AutoCommit => 1, RaiseError => 1, PrintError => 1 });
	#$dbh=abrir_db();
};
if ($EVAL_ERROR) {
    die  DBI::errstr;
}
#read the curren state 
sub getState($)
{
	my $fileName = shift (@_);
	if ( ! -e $fileName ) {
		 my $empty= {};
		 $empty{"cache"}={};
		lock_store(\%empty,$fileName);
	}
	my $state=lock_retrieve($fileName);
	return $$state{"cache"};
}
#save the curren state
sub putState($$)
{
	my $fileName = shift (@_);
	my $info = shift (@_);
	$$state{"cache"}=$info;
	lock_store $state, $fileName;
}

sub getLogFileUrl() {
	logInfo("searching access log url on db ");	
	my $sqlSearchLogFileUrl =" SELECT value FROM config  WHERE name=?";
	my $handleSearchLogFileUrl = $dbh->prepare($sqlSearchLogFileUrl);
	

	$handleSearchLogFileUrl->execute("LOG_FILE");
    my @row = $handleSearchLogFileUrl->fetchrow_array();
	
	my ($log) = @row;
	if(defined $log){
		$logFile = $log;
	}else{
		die "could not open open! $!";
		
	}

	
}

$cache=getState($cacheFile);
## SQL query
my $sqlSearchUser ="SELECT id FROM users  WHERE username=?";

my $sqlAddUser ="INSERT INTO users(username,name,email,email_verified_at,password,cuota,active,remember_token,created_at,updated_at) VALUES(?,'squid',?,NOW(),'squid',1,?,null,NOW(),NOW())";
my $handleSearchUser = $dbh->prepare($sqlSearchUser);
my $handleAddUser = $dbh->prepare($sqlAddUser);

my $sqlSearchDomain ="SELECT id,is_interest,percent_interest FROM domain WHERE name = ?";
my $sqlAddDomain ="INSERT INTO domain(name,is_interest,percent_interest,created_at,updated_at) VALUES(?,?,?,NOW(),NOW())";
my $handleSearchDomain= $dbh->prepare($sqlSearchDomain);
my $handleAddDomain= $dbh->prepare($sqlAddDomain);

my $sqlAddLog ="INSERT INTO loginfo(date,ip,status_code,size,operation,url,content_tipe,internal_size,created_at,updated_at,user_id,domain_id) VALUES(?,?,?,?,?,?,?,?,NOW(),NOW(),?,?)";
my $handleAddLog= $dbh->prepare($sqlAddLog);

sub searchDomain($) {
    my $domain = shift (@_);
	if(not defined $$cache{$domain}{"id"}){
		logInfo("the domain is not indexed, searching on db $domain");
		
		$handleSearchDomain->execute($domain);
		my @row = $handleSearchDomain->fetchrow_array();
		my ($domain_id,$domain_interest,$percent) = @row;
		
		if(not defined $domain_id){
			logInfo("is not on DB adding $domain");
			$domain_interest =0;
			$percent =0;
			if( $domain =~ m/\.cu$/){
				$domain_interest =1;
				$percent =100;
			}	
			$handleAddDomain->execute($domain,$domain_interest,$percent);
			$domain_id = $handleAddDomain->last_insert_id(undef, undef, "domain", undef);
		}
		
		$$cache{$domain}{"id"}=$domain_id;
		$$cache{$domain}{"interest"}=$domain_interest;
		$$cache{$domain}{"percent"}=$percent;
	
		#putState($cacheFile,$cache);
	}
	return $$cache{$domain}{"id"};
	
}

sub searchUser($) {
    my $user = shift (@_);
	if(not defined $$cache{"users"}{$user}){
		logInfo("the user is not indexed, searching on db $user");
		
		$handleSearchUser->execute($user);
		my @row = $handleSearchUser->fetchrow_array();
		my ($userId) = @row;
		
		if(not defined $userId){
			logInfo("is not on DB adding $user");
			my $uniqid = suniqid;
			my $active = $dbDriver eq "Pg" ? false : 0;
			$handleAddUser->execute($user,"$uniqid\@localhost",$active);
			$userId = $handleAddUser->last_insert_id((undef, undef, "users", undef));
			
		}
		
		$$cache{"users"}{$user}=$userId;
		

	
		putState($cacheFile,$cache);
	}
	return $$cache{"users"}{$user};
	
}
#search for access log url on db
getLogFileUrl();


#ciclo principal
logInfo("reading $logFile.\n");
my $lineNumber=0;
my $start=0;
open(my $file_handle, '<', $logFile) or die "could not open open ! $!";


while(<$file_handle>) {
	    my $line = $_;
		
		chomp;
		s/#.*//;
		s/^\s+//;
		s/\s+$//;
		if (m/^$/) { next; }
		my @line = split /\s+/;
		my $upat=shift @line;
		if ($upat eq '') {
			next;
		}
				
#	1541417160.906   1115 10.0.1.252 TCP_MISS/200 32353 CONNECT www.youtube.com:443 roilan FIRSTUP_PARENT/192.168.100.4 -	

	  if ( (m#^(\d+)\.\d+\s+(\d+)\s+([^\s]+)\s+(\w+)/(\d+)\s+(\d+)\s+(\w+)\s+([^\s]+)\s+([\w\-\.]+)\s+(\w+)/([\w\.\-]+)\s+([\w\/\-]*)\s*(.*)#)) {

		# 0=date 1=transfer-msec? 2=ipaddr 3=status/code 4=size 5=operation
		# 6=url 7=user 8=method/connected-to... 9=content-type
		my $stamp=$1;
	    my $date   = strftime ("%Y-%m-%d %H:%M:%S", localtime($stamp));
	    my $elapsed = $2;
        my $ip    = $3;
		my $status    = $4;
        my $code    = $5;
        my $bytes    = $6;
		my $method    = $7;
		my $url     = $8; 
        my $user   = $9;
		my $cache   = $10;
		my $ipcache   = $11;
		my $mime   = $12;
	    my $mac   = ($13 eq ""?"-":$13);

		if ($start eq 0){
			$start = 1;
			$tmpLogFile = $tmpLogDir.$stamp.".db";
			logInfo("first line, get cache ".$tmpLogFile." ");
			$cacheLog = getState($tmpLogFile);
			if (defined $$cacheLog{"locked"}){
				logInfo("previously read file  $tmpLogFile");
				if($$cacheLog{"locked"}){
					my $tmpPointer = $$cacheLog{"pointer"};
					logInfo("pointer in use, waiting 5 seconds ");
					sleep(5);
					$cacheLog = getState($tmpLogFile);
					if( $tmpPointer ne $$cacheLog{"pointer"}){
						logInfo("pointer in use, finish");
						last;
					}
				}
				logInfo("skiping reded lines ".$$cacheLog{"pointer"});
				seek($file_handle,$$cacheLog{"pointer"},0);
				next;
			}else{
				logInfo("first time reading the file, locking  $tmpLogFile");
				$$cacheLog{"locked"} = 1;
			}
		}

		if( $url =~ m/(NONE:\/|internal:\/)/ ){
			logInfo("skiping invalid line  $lineNumber - $url");
			next;
		}
		
		if($status eq "NONE" or $status eq "NONE_ABORTED" ){
			logInfo("skiping invalid line  $lineNumber - $status");
			next;
		}
		
		if ($user eq '') { next; }
		
        if ($url eq "http://detectportal.firefox.com/success.txt"){
            next;
        }
		if($status eq "TCP_DENIED" ){next;}
		
		if( $url =~ m/:\d+/){
			if( $url =~ m/:443/){
				$url=~ s/:443/\//;
			}
			if($method eq "CONNECT"){
			$url=~ s/:(\d+)/:$1\//;
			$url="https://".$url;
			}
		}
		
		my $u1 = URI->new($url); 

		$lineNumber++;
		logInfo("reading  ".$lineNumber);		
		my $domainId= searchDomain($u1->host);
		my $internalSize = $bytes;
		if($$cache{$u1->host}{"interest"}){
			$internalSize=$internalSize-($internalSize*$$cache{$u1->host}{"percent"}/100);
		}		
		my $userId = searchUser($user);
		

		$handleAddLog->execute($date,$ip,$status."/".$code,$bytes,$method,$url,$mime,$internalSize,$userId,$domainId);
		$$cacheLog{"pointer"} = tell($file_handle);
		logInfo("pointer  ".$$cacheLog{"pointer"});	
		putState($tmpLogFile,$cacheLog);

	
	  }
 
}
$$cacheLog{"locked"} = 0;
putState($tmpLogFile,$cacheLog);
logInfo("end of file. $lineNumber lines");
$handleSearchDomain->finish();
$handleAddDomain->finish();
$handleAddUser->finish();
$handleSearchUser->finish();
$dbh->disconnect();

close $file_handle;
