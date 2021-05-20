#!/usr/bin/perl -w
# Copyright 2020; Provided as-is
# Documentation: https://www.ibm.com/support/knowledgecenter/SS8JFY_9.2.0/com.ibm.lmt.doc/Inventory/tutorials/l_migrating_software_assignments_1.html

use strict;

use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use XML::LibXML::SAX;
use XML::Simple;
use XML::SAX;
use XML::SAX::Expat;
use XML::SAX::PurePerl;
use LWP::UserAgent;
use LWP::Protocol::https;
use Data::Dumper;
use HTTP::Request;
use URI::Escape;
use JSON;
use Term::ReadKey;
use Excel::Writer::XLSX;
use Getopt::Long;

## This will be a hashref of global parameters
my $config = {};

## Set some defaults for the BigFix config settings
## These may be overridden by an XML config file and/or
## command line switches
$config->{srcserver} = "gm7.swglab.fr.ibm.com";
$config->{srcport}   = 9081;
$config->{srctoken}   = "f665de1a3a70c29bdd952f640906e0519a4aa0f6";
## We do NOT want to store cleartext MO passwords in code!
$config->{outputname} = "migration-classification.out";
$config->{debug} = "No";
$config->{simulation} = "Yes";
$config->{classification} = "Non";
$config->{exclusion} = "Non";
$config->{inputserver} = "";
$config->{silent} = "Yes";

## At the moment, we do not REQUIRE a default config XML
## If present, they override the defaults
my $ec = eval { %{$config} = ( %{$config}, %{ XMLin() } ); };

## And command line options override them all
GetOptions(
	"srcserver=s"  => \$config->{srcserver},
	"srcport=s"    => \$config->{srcport},
	"srctoken=s"    => \$config->{srctoken},
	"destserver=s"  => \$config->{destserver},
	"destport=s"    => \$config->{destport},
	"desttoken=s"    => \$config->{desttoken},
	"debug=s"     => \$config->{debug},
	"simulation=s"     => \$config->{simulation},
	"classification=s" => \$config->{classification},
	"exclusion=s" => \$config->{exclusion},
	"inputserver=s" => \$config->{inputserver},
	"silent=s" => \$config->{silent},
	"outputname=s"   => \$config->{outputname}
);


## crée un agent
my $ua  = LWP::UserAgent->new();
## Remove the SSL cert and name validation
$ua->{ssl_opts}->{SSL_verify_mode} = SSL_VERIFY_NONE;
$ua->{ssl_opts}->{verify_hostname} = 0;

my $debug = 0;
if ($config->{debug} eq "Yes") { $debug = 1; open( FILEDEBUG, '>', $config->{outputname}.".out") or die $!; };
my $silent = 0;
if ($config->{silent} eq "Yes") { $silent = 1; open( FILEOUTPUT, '>', $config->{outputname}.".log") or die $!; };

# Servers selector file ?
my @selectServers;
my $selection=0;
if ($config->{inputserver} ne "") {
	$selection=1;
	open (LIRE, $config->{inputserver}) or die "Impossible Ouverture Fichier : $!\n";
	while(<LIRE>){
	push @selectServers,$_ ; 
	}
	writeMsg(":Selected:$_") foreach @selectServers;
	close (LIRE);
	}

## All the preliminaries are out of the way. RUN THAT MIGRATION!
print "\nMigration begins, Version 1.4";
print ", Mode simulation " . $config->{simulation} . ", Classification " . $config->{classification} . ", Exclusion " . $config->{exclusion} . ", Silent " . $config->{silent};
if ( $selection ) { print ", Restricted to servers in the list: ".$config->{inputserver} . "\n" } else {print "\n"};

# Working on source data
my $srcbase = "https://".$config->{srcserver}.":".$config->{srcport}."/";
my $srctoken = $config->{srctoken};
my $srcversion = processVersion ($srcbase, $srctoken );
print " -- Querying Source     |" . $config->{srcserver} . " | port:" . $config->{srcport} ." | version:" . $srcversion ;
my $srcServersRaw = queryServers ($srcbase, $srctoken );
my @srcServers = @{ $srcServersRaw->{'rows'} };
my %srcServerNames;

for my $item( @{$srcServersRaw->{'rows'}} ){
	# Création d'un array pour la source cle=hostname, valeur =bigfix id
	$srcServerNames{$item->{'name'}} = $item->{'bigfix_id'};
	};

# Working on destination data
my $destbase = "https://".$config->{destserver}.":".$config->{destport}."/";
my $desttoken = $config->{desttoken};
my $destversion = processVersion ($destbase, $desttoken );
print " -- Writing Destination |" . $config->{destserver} . " | port:" . $config->{destport} ." | version:" . $destversion ;
my $destServersRaw = queryServers ($destbase, $desttoken );
my @destServers = @{ $destServersRaw->{'rows'} };


if ($config->{classification} eq "Yes") {
# Recherche des classifications

writeMsg ("\n Classifications.");
writeMsg ("\n Server | ID interne | Bigfix ID Destination | Bigfix ID Source | #Components source | #Valid Instances Confirmed | # Valid Instances Bundled | #Instances unmodified | #Instances Invalid | Reasons Invalid Instances |") ;

foreach my $server ( @destServers ) {
	# On ne prend que les serveurs selectionnes
	if ( $selection ) {
		if ( ! grep /^$server->{'name'}$/, @selectServers ) { writeMsg("\nskipped :".$server->{'name'}); next };
	};
	
	my $destComputer_bigfix_id = $server->{'bigfix_id'};
	my $destComputer_interne_id = $server->{'id'};
	my $line = "\n" .$server->{'name'} . "|" . $destComputer_interne_id . "|". $destComputer_bigfix_id . "|";
	
	if( exists( $srcServerNames{$server->{'name'}} ) ) {
		my $srcComputer_bigfix_id = $srcServerNames{$server->{'name'}} ; # recherche bigfix-id par la cle du name
		$line = $line . $srcComputer_bigfix_id . "|";
		if ($silent) { print $destComputer_interne_id . "\n" }; 
		# Recherche de logiciels sources de ce serveur
		my $url = "${srcbase}api/sam/v2/software_instances?token=${srctoken}";
		$url = $url . "&limit=150&columns[]=product_name&columns[]=component_name&columns[]=discovery_path&columns[]=is_charged&columns[]=is_confirmed&columns[]=computer_dns_name&columns[]=discoverable_guid&columns[]=product_release_guid&columns[]=metric_id";
		$url = $url . "&criteria=\{\"and\":[[\"is_present\",\"=\",\"1\"],[\"computer_bigfix_id\",\"=\",\"${srcComputer_bigfix_id}\"]]}";
		my $contSoft = processURLbrut($url);
		my $compSoft = decode_json ($contSoft);
		$line = $line . $compSoft->{'total'} . "|" ;
		
		if ( $debug ) { print FILEDEBUG "\n" . $line . "\n"; print FILEDEBUG Dumper ($compSoft); };
		
		# Ecriture des classifications de ce serveur
		if ($config->{simulation} eq "Non") {
			my $url = "${destbase}/api/sam/v2/software_instances?token=${desttoken}";
			$url = $url . "&verbose=true";
			my $contPutSoft = processURLput( $url , $contSoft );
			$line = $line . analysePutSoftdebug ($contPutSoft);
			$line = $line . "Migrated";
			
		} else {
			
			# Recherche de logiciels sources de ce serveur
			my $url = "${destbase}/api/sam/v2/software_instances?simulate=true&verbose=true&token=${desttoken}";
			my $contPutSoft = processURLput( $url , $contSoft);
			$line = $line . analysePutSoftdebug ($contPutSoft);
			$line = $line . "Simulated";
		}	

	} else {
		$line = $line . "No source Bigfix id found|";
	}
	writeMsg($line);
	}
}

if ($config->{exclusion} eq "Yes") {

# Recherche des exclusions
writeMsg( "\n\n Exclusions.");
writeMsg( "\n Serveur | Internal ID | Bigfix ID Destination | Bigfix ID Source | #exclusions | Details...") ;

foreach my $server ( @destServers ) {
	# On ne prend que les serveurs selectionnes
	if ( $selection ) {
		if ( ! grep /^$server->{'name'}$/, @selectServers ) { writeMsg("\nskipped :".$server->{'name'}); next };
	};
	
my $serverName=$server->{'name'};
my $destComputer_bigfix_id = $server->{'bigfix_id'};
my $destComputer_interne_id = $server->{'id'};
my $line = "\n" . $serverName . "|" . $destComputer_interne_id . "|" . $destComputer_bigfix_id . "|";
	
	if( exists( $srcServerNames{$server->{'name'}} ) ) {
		# Recherche de logiciels exclus de ce serveur
		if ($silent ) { print  $destComputer_interne_id . "\n" }; 
		my $url = "${srcbase}api/sam/v2/software_instances?token=${srctoken}";
		$url = $url . "&columns[]=instance_id&columns[]=component_name&columns[]=exclusion_or_suppress_comment";
		$url = $url . "&criteria=\{\"and\":[[\"is_excluded\",\"=\",\"1\"],[\"computer_name\",\"=\",\"${serverName}\"]]\}" ;
		my $Exclusions = processURL($url);
		$line = $line . $Exclusions->{'total'} . "|" ;
		# Pour chaque ligne exclue on retrouve la meme dans la destination
		for my $itemExclu( @{$Exclusions->{'rows'}} ){
	# Création d'un array contenant les exclusions
			my $instance_id=$itemExclu->{'instance_id'};
			my $exclusion_or_suppress_comment=$itemExclu->{'exclusion_or_suppress_comment'};
			my $component_name=$itemExclu->{'component_name'};
			my $updateTime=1349237658578;
			$line = $line . "S:" . $instance_id . " | " . $exclusion_or_suppress_comment . " | ";
	# Recherche des instances équivalentes dans la destination
			my $url = "${destbase}/api/sam/v2/software_instances?token=${desttoken}";
			$url = $url . "&columns[]=computer_id&columns[]=instance_id&columns[]=component_name" ;
			$url = $url . "&criteria=\{\"and\":[[\"computer_bigfix_id\",\"=\",\"${destComputer_bigfix_id}\"],[\"component_name\",\"=\",\"${component_name}\"]]\}";
			my $contJsonSoft = processURL ($url);
	        if ( $debug ) {print FILEDEBUG "EXCLUSION\n"; print FILEDEBUG Dumper($contJsonSoft);} ;
			if ($config->{simulation} eq "Non") {
			# Pour chaque instance il faut l'exclure
			# POST /api/sam/swinventory/exclude
				for my $itemExcluDest( @{$contJsonSoft->{'rows'}} ) {
					my $instance_idDest= $itemExcluDest->{'instance_id'} ;
					$line = $line . "D:" . $instance_idDest . "|" ;
					my $reqDest = HTTP::Request->new( POST => "${destbase}/api/sam/swinventory/exclude?productInventoryId=${instance_idDest}&updateTime=1349237658578&reason=other&comment=${exclusion_or_suppress_comment}&token=${desttoken}" );
					my $resDest = $ua->request($reqDest);
	#print $resDest;	
					if ( !$resDest->is_success ) {
						print STDERR "HTTP POST Error code: [" . $resDest->code . "]\n";
						print STDERR "HTTP POST Error msg:  [" . $resDest->message . "]\n";
						exit 1;
					}	
					if ( $debug ) {print FILEDEBUG "EXCLUSION\n"; print FILEDEBUG Dumper ($resDest);} ;
				}
			} else { $line = $line . "Simulated |" }	
	#	if ( $debug ) {print FILEDEBUG "ECRITURE\n"; print FILEDEBUG Dumper ($compPutSoft);} ;
	
		};

		
		
		
	}
	else {
		$line = $line . "No source Bigfix id |";
	}
	writeMsg ($line);
	}
}

if ( $debug ) { close(FILEDEBUG);};
if ( $silent ) { close( FILEOUTPUT) ; };

exit 0;

sub analysePutSoftdebug {
	my ($putSoft) =  @_ ;
	my $json = $putSoft;
	
	my $nb_valid_instances_bundled = 0;
	my $nb_invalid_instances = 0;
	my $label_invalid_instances = ".";
	my $nb_unmodified_instances = 0;
	my $nb_vi_confirmed = 0;

	if ($debug) { print FILEDEBUG "analysePutSoftdebug:entree" . Dumper ($json) };
	while (my ($key, $value) = each(%$json)) {
		if ($debug) { print FILEDEBUG "analysePutSoftdebug:key-value" . $key . "|" . Dumper ($value) ."\n" };
		next unless ref $value;            # skip if $value isn't a ref
		next if scalar (keys %$value) < 2;  # skip if the numbers of HASH keys < 2
		if ($debug) { print FILEDEBUG "analysePutSoftdebug:" . $key ."|". Dumper ($value->{valid_instances}->{Confirmed}) ."\n" };
		if ($key eq "summary") {
			if (defined ($value->{valid_instances}->{Confirmed})) {$nb_vi_confirmed= $value->{valid_instances}->{Confirmed}} else {$nb_vi_confirmed=0 };
			
			if (defined ($value->{valid_instances}->{Bundled})) {$nb_valid_instances_bundled = $value->{valid_instances}->{Bundled} } else {$nb_valid_instances_bundled=0};
			
			if (defined ($value->{unmodified_instances})) {$nb_unmodified_instances = $value->{unmodified_instances} } else { $nb_unmodified_instances=0};
			
			my $invalid_instances = decode_json ( encode_json ($value->{invalid_instances} ));
			
			while (my ($iikey, $iivalue) = each (%$invalid_instances)) {
				$nb_invalid_instances += $iivalue;
				$label_invalid_instances = $label_invalid_instances . ":" . $iikey ;
				if ( $debug ) { print FILEDEBUG "analysePutSoftdebug:invalid instances" . $iikey . "|" . $iivalue . "|" } ;
				next unless ref $iivalue;
				next if scalar (keys %$iivalue) < 2;
				
				}
			}
		}

	my $line = $nb_vi_confirmed . "|" . $nb_valid_instances_bundled . "|" . $nb_unmodified_instances . "|" . $nb_invalid_instances . "|" . $label_invalid_instances . "|" ;
	return $line;

}


sub queryServers {
# Recherche des serveurs présents
# DOC: https://www.ibm.com/support/knowledgecenter/SS8JFY_9.2.0/com.ibm.lmt.doc/Inventory/integration/r_get_computers_v2.html#new_get_software_instances

	my ( $srcbase, $srctoken ) = @_;
	my $url = "${srcbase}api/sam/v2/computers?token=${srctoken}";
	$url = $url . "&columns[]=name&columns[]=last_seen&columns[]=id&columns[]=bigfix_id";
	$url = $url . "&criteria=\{\"and\":[[\"last_seen\",\"last\",\"P1M\"],[\"is_deleted\",\"=\",\"0\"]]\}" ;
	my $Servers = processURL($url);
	print "| " . $Servers->{'total'} . " servers \n" ;
	return $Servers;
}

sub processVersion {
	my ( $srcbase, $srctoken , $version ) = @_;
	my $url = "${srcbase}api/sam/about?token=${srctoken}";
	my $reponse = processURL($url) ;
	$version = $reponse->{'version'};
	return $version;
}

# Lance une URL get et retourne le résultat brut
sub processURLbrut {
	my ($url) = @_;
	if ( $debug ) {
		print FILEDEBUG "\n URL: ";
		print FILEDEBUG Dumper ($url);
		}		;
	my $requete = HTTP::Request->new( GET => "${url}" );
	my $reponse = $ua->request($requete);
	if ( !$reponse->is_success ) {
		print STDERR "HTTP POST Error code: [" . $reponse->code . "]\n";
		print STDERR "HTTP POST Error msg:  [" . $reponse->message . "]\n";
		if ( $debug ) {
			print FILEDEBUG "HTTP POST Error code: [" . $reponse->code . "]\n";
			print FILEDEBUG "HTTP POST Error msg:  [" . $reponse->message . "]\n";
		};
		exit 1;	
	}	
	## lecture et decodage de la réponse
	my $contenuDeLaReponse = $reponse->content ;
	return $contenuDeLaReponse;
}

# Lance une URL get et retourne le résultat JSON decodé
sub processURL {
	my ($url ) = @_ ;
	my $contenuDeLaReponse = processURLbrut($url);
	my $decodeResponse = decode_json ( $contenuDeLaReponse );
	#print  Dumper($decodeResponse) ;
	return $decodeResponse;
}

# Lance une URL put avec contenu, et renvoie le résultat JXON decodé
sub processURLput {
	my ($url , $contSoft ) = @_ ;
	my $putSoft = HTTP::Request->new( PUT => "${url}" );
	$putSoft->content($contSoft);
	## récupère la réponse
	my $resPutSoft = $ua->request($putSoft);
	#print $resPutSoft;
	if ( !$resPutSoft->is_success ) {
		print STDERR "HTTP POST Error code: [" . $resPutSoft->code . "]\n";
		print STDERR "HTTP POST Error msg:  [" . $resPutSoft->message . "]\n";
		if ( $debug ) {
			print FILEDEBUG "ECRITURE HTTP POST Error code: [" . $resPutSoft->code . "]\n";
			print FILEDEBUG "ECRITURE HTTP POST Error msg:  [" . $resPutSoft->message . "]\n";
		};
		exit 1;
	}	
	## lecture de la réponse
	my $contPutSoft = $resPutSoft->content ;
	my $compPutSoft = decode_json ( $contPutSoft );

	if ( $debug ) {print FILEDEBUG "ECRITURE\n"; print FILEDEBUG Dumper ($compPutSoft);} ;
	return $compPutSoft;

}
sub writeMsg {
	my ($Msg) = @_;
	if ( $silent ) {print FILEOUTPUT $Msg} else {print $Msg} ;
	if ( $debug ) { print FILEDEBUG $Msg; };
	
}
