#!/usr/bin/perl
############################################################
#
# File: Install.PL
#
# Description: 
# This script will automatically install or update all the 
# necessary modules required by Report Magic, install Report 
# Magic in the destination directory, along with documentaion.
# NOTE: This will update all modules on your system that 
# Report Magic uses to the latest stable version available.
#
# Arguments:
#      -no_modules    Will not do the CPAN Perl module update
#      -only_modules  Will just do the CPAN Perl module update
#
# Created: 1999.Oct.18 by Jeremy Wadsack for Wadsack-Allen Digital Group
# 	Copyright (C) 1999, 2002 Wadsack-Allen. All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the Artistic License as described in 
# docs/license.html
############################################################
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999NOV18 First working version                        JW
# 1999DEC16 Rearranged notice to be proper order         JW
# 2000JAN11 Converted to full install script             JW
# 2000FEB14 Update for RM 1.3                            JW
# 2000MAR08 Patched for RM 1.31                          JW
# 2000MAR30 Added error checking to copy function        JW
# 2000MAR30 Added install support for GDGraph3d          JW
# 2000APR04 Added wadg::* libraries to install           JW
# 2000JUL19 Changed W/WA/WADG/... to GD::Graph3d         JW
# 2000Jul24 Changed IniConf to Config::IniFiles          JW
# 2000Aug24 Changed default install to something logical JW
# 2000Sep29 Fixed for 2.0 changes                        JW
# 2000Nov28 Added error handling and CPAN autoload       JW
# 2001Feb05 Changed $DEST on --only-modules mode         JW
# 20Dec2001 Disabled CPAN auto-update (gets Perl 5.6.1)  JW
# 08Aug2002 Changed logos to PNG format                  JW
# 21Mar2003 Added File::Temp to modules list             JW
# 24Mar2003 Patched to make sure .root is installed      JW
############################################################
use strict;
use File::Copy;
use File::Path;
use Cwd;
use vars qw( $DEST $DOC $FILE_MODE $EXEC_MODE );

#
# The following configurations may be made to modify the install
# on your system. 
#

#
# Where do you want Report Magic to be installed
# You can use the pattern $(VERSION) as in this 
# example to use the version number in your path. 
# Make sure this remains in single quotes.
#
$DEST = '/usr/local/bin/rmagic-$(VERSION)/';
 
#
# Where do you want documentation to be installed?
# You can use string concatenation, as in this example, 
# to install the docs below the program.
$DOC = $DEST . 'docs/';


#
# These set the permissions for all installed files. 
# FILE_MODE is the default mode for all installed files 
# including docs, configuration files and libraries.
# EXEC_MODE is used for the script.
#
$FILE_MODE = 0644;
$EXEC_MODE = 0755;


#
# #################### END OF CONFIGURATION ####################
#  [You should not need to change anything below here]
# ##############################################################

my @modules;
@modules = qw( GD Config::IniFiles File::Spec HTML::Tagset HTML::Parser GD::Text GD::Graph GD::Graph3d File::Temp );
my @no_up;
@no_up = qw( GD File::Spec HTML::Parser );
my $cnt = 0;
my $VERSION = '2.21';
my %args;
my $err_cnt = 0;

# Parse command line
foreach ( @ARGV ) {
	if( /^--?([^=]+)=?(.*)$/ ) {
		my( $k, $v ) = ($1, $2);
		$k =~ s/-/_/;
		$args{$k} = $v;
	} else {
		$DEST = $_;
		$DOC = $DEST . 'docs/';
	} # end if
} # end foreach


# Convert DEST, DOC
$DEST =~ s/\$\(VERSION\)/$VERSION/g;
$DOC =~ s/\$\(VERSION\)/$VERSION/g;
if( $DEST !~ m#/$# ) {
	$DEST .= '/';
} # end if
if( $DOC !~ m#/$# ) {
	$DOC .= '/';
} # end if

# Get CWD for later ('cause CPAN module is poorly behaved!)
my $cwd = cwd;

# Output header
print qq[
------------------------------------------------------

 Report Magic $VERSION installation script

------------------------------------------------------

];

# Install c libraries.

#print qq[

#In order to install Report Magic for Analog, several system libraries
#must be installed. These include zlib, libpng, and libgd. This script 
#will not install the True Type Fonts library lttf. If you want support 
#for True Type fonts in Report Magic, please install this library by 
#hand from http://www.freetype.org/, then rerun the install script.

#To continue with library installation press [ENTER].];
#getc; print "\n\n";


#       zlib http://www.cdrom.com/pub/infozip/zlib/
#           ftp://ftp.cdrom.com/pub/infozip/zlib/zlib.tar.gz
#           make install
#       libpng http://www.cdrom.com/pub/png/
#           http://www.cdrom.com/pub/png/src/libpng-1.0.5.tar.gz
#           mv ../zlib* zlib
#           cd ..; mv libpng* libpng; cd libpng
#           cp scripts/makefile.stf Makefile
#           make install
#       libgd http://www.boutell.com/gd/
#           ftp://ftp.boutell.com/pub/boutell/gd/gd-1.7.3.tar.gz


# Install Perl Modules

unless( defined $args{no_modules} || $err_cnt ) {
	print "This script will install or upgrade the following modules:\n";
	print map( "\t$_\n", @modules );

	print qq{

The CPAN interface will now attempt to locate your nearest archive
and install modules from there. If this is the first time you have
run the CPAN shell, you will need to provide some configuration
information. If, when asked for your favorite CPAN site, you are not 
given a list to choose from you can type in 'ftp://ftp.cpan.org/CPAN'.

Press [ENTER] to continue.};
	getc; print "\n\n";

	require CPAN;

	# Update the CPAN module 
	my $cpan = CPAN::Shell->expand( 'Bundle', 'Bundle::CPAN' );
#	unless( $cpan->uptodate ) {
#		$cpan->install;
#		CPAN::Shell->reload( 'cpan' );
#	} # end unless

	my @packages = map( CPAN::Shell->expand( 'Module', $_ ), @modules );
	
	print qq[

The CPAN shell has located your nearest archive and will begin
installing the necessary Perl modules now.

];

	my $mod;
	for $mod ( @packages ) {
		if( CPAN::Shell->format_result( 'Module', $mod->id ) =~ /INST_VERSION\s+\d+/ ) {
			my $id = $mod->id;
			if( grep( /$id/, @no_up ) ) {
				print "\n" . $mod->id . " is installed; not upgrading.\n";
			} elsif( $mod->uptodate ) {
				print "\n" . $mod->id . " is up to date.\n";
			} else {
				print "\nUpgrading module " . $mod->id . "...\n";
				$mod->install;
				unless( $mod->uptodate ) {
					$err_cnt++;
					last;
				} # end if
			} # end unless
		} else {
			print "\nAdding module " . $mod->id . "...\n";
			$mod->install;
			unless( $mod->uptodate ) {
				$err_cnt++;
				last;
			} # end unless
		} # end if
		$cnt++;
	} # end for

	print "$cnt module installed or updated.\n" if $cnt == 1;
	print "$cnt modules installed or updated.\n" if $cnt > 1;
	print "$err_cnt module failed to install!\n" if $err_cnt == 1;
	print "$err_cnt modules failed to install!\n" if $err_cnt > 1;
} # end unless


#
# Now install Report Magic
#
unless( defined $args{only_modules} || $err_cnt ) {
	chdir( $cwd );
	print "Installing Report Magic files in $DEST.\n";
		# make sure $DEST exisits
		if( !-d $DEST ) {
			print "... Path does not exits, making it.\n";
			mkpath( $DEST );
		} # end if
		&install( $FILE_MODE, 'README', $DEST ) || $err_cnt++;
	print "... Installing Report Magic image files.\n";
		&install( $FILE_MODE, 'rmlogo.png', $DEST ) || $err_cnt++;
		&install( $FILE_MODE, 'analogo.png', $DEST ) || $err_cnt++;
	print "... Installing Report Magic sample files.\n";
		&install( $FILE_MODE, 'samples/', $DEST.'samples/' ) || $err_cnt++;
		&install( $EXEC_MODE, 'rmagic.sample', $DEST ) || $err_cnt++;
		&install( $EXEC_MODE, 'sample.dat', $DEST ) || $err_cnt++;
	print "... Installing Report Magic language files.\n";
		&install( $FILE_MODE, 'lang/', $DEST.'lang/' ) || $err_cnt++;
	print "... Installing Report Magic program files.\n";
		&install( $EXEC_MODE, 'rmagic.pl', $DEST ) || $err_cnt++;
		&install( $FILE_MODE, 'wadg/', $DEST.'wadg/' ) || $err_cnt++;

	#
	# Now install Report Magic Documentation
	#

	print "Installing documentation in $DOC.\n";
		&install( $FILE_MODE, 'docs/', $DOC ) || $err_cnt++;
		&install( $FILE_MODE, 'docs/images/', $DOC.'images/' ) || $err_cnt++;

} # end unless

if( $err_cnt ) {
	print "\n*** Installation Failed! ***\n";
	print "Please review the output of the installation above \n";
	print "to determine where the problem occurred and try to \n";
	print "correct the situation. Often, by reading the error \n";
	print "messages you can determine what needs to be changed.\n";
} else {
	$DOC = 'docs/' if defined $args{only_modules};
	print "\nInstallation complete.\n";
	print "For help on using Report Magic see $DOC"."index.html.\n";
	print "You must agree to the license agreement at $DOC"."license.html before using Report Magic.\n";
} # end if


exit $err_cnt;

#
# Install (copy) files from one place to another, setting mode
# NOTE: $src CANNOT be an absolute filename. It should be 
# relative to the $dest directory if $dest is a directory.
#
sub install {
	my( $mode, $src, $dest ) = @_;
	my $rc = 1;
	if( -d $src ) {
		# make sure $dest exisits
		if( !-d $dest ) {
			mkpath( $dest );
		} # end if
		# copy each file, recursing subdirectories
		my $file;
		opendir(DIR, $src) || die "Error: Can not read directory $src: $!";
			foreach $file (readdir(DIR)) {
				next if $file eq '.' || $file eq '..';
				$file =~ s/\.dir$// if $^O eq 'VMS' && -d "$src/$file";
				&install( $mode, "$src/$file", "$dest/$file" );
			} # end foreach
		closedir DIR;		
	} else {
		if( -d $dest ) {
			$dest .= $src;
		} # end if
		if( copy( $src, $dest ) ) {
			chmod( $mode, $dest );
		} else {
			print "\t***Error: Can not copy $src to $dest. $!.\n";
			$rc = 0;
		} # end if
	} # end if
	return $rc;
} # end install

