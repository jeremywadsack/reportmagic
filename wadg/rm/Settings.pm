############################################################
#
# Module: wadg::rm::Settings
#
# Created: 20.March.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 1999,2002 Wadsack-Allen. All rights reserved.
# Based on subs from Report Magic (19.Feb.1999-20.Mar.2000)
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
# 16Feb1999 Created by Corey Kaye / DNS                   CK
# 26May2000 Converted to a Config::IniFiles subclass      JW
# 26May2000 Removed all file processing, now only allows
#           ini style configuration files.                JW
# 14Jun2000 Converted data structure mods to method calls JW
############################################################
package wadg::rm::Settings;
use strict;

BEGIN {
	use vars       qw($VERSION @ISA);

	$VERSION = do { my @r = (q$Revision: 2.20 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

	@ISA         = qw( Config::IniFiles );
} # end BEGIN

# non-exported package globals go here
# These two package globals are used to store the
# known settings and report names from the list 
# at the end of the package
use vars      qw( %KNOWN_SETTINGS @KNOWN_REPORTS %KNOWN_REPORTS );

use Config::IniFiles;
use File::Basename;
use wadg::Errors;

##########################
##                      ##
##   TIEHASH Methods    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: TIEHASH
#
# Args: {named parameter list}
#  -argv 	A list of command-line options to parse as settings
#  -preset 	A list of pre-set options to include in settings
#	-version A message printed out for the --version command
#  -<any>	Any valid Config::IniFiles parameters
#
# Description: Contructs an object tied to the hash 
#              with a tie call. The -argv list is parsed for 
#              settings file names and overrides =~ -.*
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Mar21 Created the function                          JW
# 2000Jun14 Fixed include file processing                 JW
# 29Jul2002 Fixed -default issue with -import using existsJW
# 05Dec2002 Looks in script dir for config file last      JW
# 27Feb2003 Added CGI mode parameter processing           JW
# 09Mar2003 Added -preset because -arg is ignored in CGI  JW
# ----------------------------------------------------------
sub TIEHASH {
	my $class = shift;
	my %parms = @_;
	
	# Save version value
	# -- This is distinct from {_INTERNAL}{_VERSION} which is just a number. 
	#    This is the message to print for the -v command-line option
	my $version = delete $parms{-version};
	
	# Get filename from command line
	my @args = ();
	@args = @{$parms{-argv}} if defined $parms{-argv};
	delete $parms{-argv};
	my @filenames = grep /^[^-]/, @args;

	# Get the preset options here to add later
	my %preset = ();
	%preset = %{$parms{-preset}} if exists $parms{-preset};
	delete $parms{-preset};

	# If no filenames then look in cwd, then in installed dir
	unless( @filenames ) {
		my $base;
		( $base, undef , undef ) = fileparse( $0, '\..*' );
		
		# Start in current directory
		my $dir = File::Spec->curdir;
		if( opendir( DIR, $dir ) ) {
			push @filenames, map {File::Spec->catfile( $dir, $_ )} grep { /^$base\..+/i && -f File::Spec->catfile( $dir, $_ ) } readdir(DIR);
			closedir DIR;
		} # end if
		
		# Then look in script directory
		if( defined $FindBin::RealBin ) {
			$dir = $FindBin::RealBin;
			if( opendir( DIR, $dir ) ) {
				push @filenames, map {File::Spec->catfile( $dir, $_ )} grep { /^$base\..+/i && -f File::Spec->catfile( $dir, $_ ) } readdir(DIR);
				closedir DIR;
			} # end if
		} # end if
	} # end unless


	# But don't match the script / executable name!
	my $progname = fileparse( $0 );
	@filenames = sort( grep !/^$progname$/i, @filenames );

	# Create a new object, passing settings, and bless into our class
	# try each filename in the list until one of them comes up valid
	my $self = undef;
	while( @filenames ) {
		$parms{-file} = shift @filenames;
		my %hash;
		tie %hash, 'Config::IniFiles', ( %parms ) ;
		$self = tied(%hash);
		last if defined $self;
	} # end if
	return undef unless defined $self;
	return undef unless $self->Sections;

	bless( $self, $class );
	$self->{FILENAME} = $parms{-file};

	#----------------------------------------
	# Insert values that are defined in pre-set
	#----------------------------------------
	foreach( keys %preset ) {
		my $p;
		foreach $p (keys %{$preset{$_}} ) {
			$self->{v}{$_}{$p} = $preset{$_}{$p};
		} # end foreach
	} # end foreach
	
	

	#----------------------------------------
	# Recurse the settings through Include
	#----------------------------------------
	if( exists $self->{v}{statistics}{Include} ) {
		# Get the file name(s) to include
		my @files = ($self->{v}{statistics}{Include});
		@files = @{$files[0]} if ref($files[0]) eq 'ARRAY';
		# Now undef the Include setting so it can be set in the next file
		delete $self->{v}{statistics}{Include};
		
		# Then include the file, or files
		foreach( @files ) {
			$parms{-file} = $_;
			$self->_include_file( %parms );
			
			# Push any included files onto the file list and undef for next round
			if( exists $self->{v}{statistics}{Include} ) {
				my @f = ($self->{v}{statistics}{Include});
				@f = @{$f[0]} if ref($f[0]) eq 'ARRAY';
				push @files, @f;
				delete $self->{v}{statistics}{Include};
			} # end if
		} # end foreach
	} # end if
	
	
	
	#----------------------------------------
	# If in CGI mode, then load from GET/POST
	#----------------------------------------
	if( exists $self->{v}{_INTERNAL}{_CGI} ) {
		# See note in rmagic.pl about redundancy. This is here to be self-contained
		require CGI;

		# Set this up to start
		$self->{v}{CGI}{Analog_Config} = [];
		

		#
		# Make lists to hold forbidden/allowed commands
		# Use hashes for lookup speed. Also normalize settings names here
		#
		my %forbidden = ();
		my %allowed = ();
		foreach( split /\s*,\s*/, $self->{v}{CGI}{Allowed} ) {
			s/[- ]/_/;		# Normalize
			$allowed{$_} = 1;
		} # end foreach
		my $has_allowed = keys %allowed;
		foreach( split /\s*,\s*/, $self->{v}{CGI}{Forbidden} ) {
			s/[- ]/_/;		# Normalize
			$forbidden{$_} = 1;
		} # end foreach
		
		# Default value if none provided.
		# NOTE: The entire CGI section is excluded below, whatever %forbidden is set to
		unless( $has_allowed || keys %forbidden ) {
			%forbidden = map {$_ => 1} qw[statistics_File_In statistics_Include statistics_Log_File statistics_Frame_File_Out graphs_Path_To graphs_URL_To reports_File_Out navigation_File_Out navigation_Top_Logo website_Company_Logo];
		} # end  unless
		

		#
		# Do the same for Analog commands
		#
		my %A_forbidden = ();
		my %A_allowed = ();
		foreach( split /\s*,\s*/, $self->{v}{CGI}{Analog_Allowed} ) {
			s/[- ]/_/;		# Normalize
			$A_allowed{$_} = 1;
		} # end foreach
		my $has_A_allowed = keys %A_allowed;
		foreach( split /\s*,\s*/, $self->{v}{CGI}{Analog_Forbidden} ) {
			s/[- ]/_/;		# Normalize
			$A_forbidden{$_} = 1;
		} # end foreach

		# Default value if none provided.
		# This is based on anlgform.pl 5.24
		unless( $has_A_allowed || keys %A_forbidden ) {
			%A_forbidden = map {$_ => 1} qw[LOGFORMAT APACHELOGFORMAT DEFAULTLOGFORMAT APACHEDEFAULTLOGFORMAT HEADERFILE FOOTERFILE UNCOMPRESS OUTFILE CACHEOUTFILE LOCALCHARTDIR ERRFILE DNS CGI SETTINGS PROGRESSFREQ LANGFILE DESCFILE];
		} # end  unless
		

		# Parse each of the options as a Report Magic or Analog setting
		my $query = new CGI();
		my @params = $query->param();
		foreach( @params ) {
			#
			# Something like 'statistics-=' is an RM setting
			# Supports '-', '_' or ' ' to separate section from parameter names
			#
			if( /^([^_-]+)[ _-](.+)$/ ) {
				my $name  = $1;
				my $name2 = $2;
				my $val   = $query->param($_);
				   $val   = 1 if $val eq '';		# CGI 2.63 and later use '' for unvalued params
				
				# Like command-line, support '-' or '_' in parameter names
				$name2 =~ s/-/_/g;
				
				# SECURITY: Do not allow these settings from the CGI variables!
				next if $name eq 'CGI';
				
				# Check Allowed/Forbidden lists
				next if exists $forbidden{"${name}_$name2"}; 
				next if $has_allowed && !exists $allowed{"${name}_$name2"};
				
				# Store the new setting, overriding anything already set
				$self->{v}{$name}{$name2} = $val;
			} 
			#
			# Anything we don't know, pass to the Analog CGI process to deal with
			#
			else {
				
				# Check if the commands are forbidden
				next if exists $A_forbidden{$_};
				next if $has_A_allowed && !exists $A_allowed{$_};
				if( /FLOORA$/ or /1$/ ) {
					my $t = chop;
					next if exists $A_forbidden{$t};
					next if $has_A_allowed && !exists $A_allowed{$t};
				} # end if
				
				# Only get the value for those that are not handled otherwise
				my $k = uc($_);
				push @{$self->{v}{CGI}{Analog_Config}}, $self->_analog_printargs( $query, $k )
					unless($k eq 'QV' || $k eq 'CG' || $k eq 'CM' || $k =~ /FLOORB$/ ||
					       $k =~ /2$/ || $k =~ '^LOGTIMEOFFSET' || $k =~ '^WARNINGS' ||
							 # commands dealt with elsewhere
							 $k =~ /[^A-Z12]/ || $k eq '' || $k =~ /^IGNORE/);
							 # other stuff not wanted
				
			} # end if
			
		} # end foreach

		#
		# Add first Analog command to the top of the list
		#		
		if( !exists($A_forbidden{LOGTIMEOFFSET}) && (!$has_A_allowed || exists $A_allowed{LOGTIMEOFFSET}) ) {
			unshift @{$self->{v}{CGI}{Analog_Config}}, $self->_analog_printargs($query, 'LOGTIMEOFFSET');
		} # end if
		if( !exists($A_forbidden{WARNINGS}) && (!$has_A_allowed || exists $A_allowed{WARNINGS}) ) {
			unshift @{$self->{v}{CGI}{Analog_Config}}, $self->_analog_printargs($query, 'WARNINGS');
		} # end if
		unshift @{$self->{v}{CGI}{Analog_Config}}, "WARNINGS FL";
		unshift @{$self->{v}{CGI}{Analog_Config}}, "DNS NONE";
		unshift @{$self->{v}{CGI}{Analog_Config}}, "CGI ON";
		if( !exists($A_forbidden{CG}) && (!$has_A_allowed || exists $A_allowed{CG}) ) {
			unshift @{$self->{v}{CGI}{Analog_Config}}, $self->_analog_printargs($query, 'CG', 'CONFIGFILE');
		} # end if


		#
		# Add the final Analog commands that must be listed last
		#
		push @{$self->{v}{CGI}{Analog_Config}}, "DEBUG -C";
		if( !exists($A_forbidden{CM}) && (!$has_A_allowed || exists $A_allowed{CM}) ) {
			push @{$self->{v}{CGI}{Analog_Config}}, $self->_analog_printargs($query, 'CM', 'CONFIGFILE');
		} # end if
		push @{$self->{v}{CGI}{Analog_Config}}, "OUTFILE stdout";
		push @{$self->{v}{CGI}{Analog_Config}}, "OUTPUT COMPUTER";
		push @{$self->{v}{CGI}{Analog_Config}}, "COMPSEP \t";		# Force this just to know we don't use ':'


		#
		# Now set the required values for certain RM commands
		#
		delete $self->{v}{navigation}{File_Out} unless $self->{v}{navigation}{File_Out} =~ /^(LEFT|TOP|RIGHT|BOTTOM|NONE)$/i;
		delete $self->{v}{statistics}{Frame_File_Out};
		delete $self->{v}{statistics}{File_In};
		$self->{v}{reports}{File_Out} = '-';
		$self->{v}{statistics}{Always_Quit} = '1';				# So the screen isn't filled with consoles
		$self->{v}{statistics}{Verbose} =~ s/[^WEwe]//g; 		# So the error log isn't filled up
		$self->{v}{statistics}{Language} =~ s/[^A-Za-z_-]//g;	# Only safe chars in language path!
		delete $self->{v}{reports}{File_Extension};
		
		#
		# Analog must be set in config file.
		# NOTE: Don't try to auto-find, that could run something COMPLETELY unexpected!
		#
		unless( exists $self->{v}{CGI}{Analog} && -x $self->{v}{CGI}{Analog} ) {
			wadg::Errors::error( -1, 'E0017' );
		} # end unless
		
		##
		## qv=1 could be processed here like in Analog:
		#print STDOUT "<code>$_</code><br />\n" foreach( @{$self->{v}{CGI}{Analog_Config}} );

	} # end if
	
	
	#----------------------------------------
	# Get command line from parameters if not in CGI mode
	#----------------------------------------
	unless( exists $self->{v}{_INTERNAL}{_CGI} ) {
		
		# Restore version in object in case it was clobbered in an include
		$self->{version} = $version;
	
		# Then include any command-line includes
		$self->_parse_command_line( @args );
		if( exists $self->{v}{statistics}{Include} ) {
			my @files = ($self->{v}{statistics}{Include});
			delete $self->{v}{statistics}{Include};
			# Then include the file supporting included files there in
			## I'm using an array here because recursion could get really deep and 
			## ugly. This is start-up so we want it to be pretty fast
			foreach( @files ) {
				$parms{-file} = $_;
				$self->_include_file( %parms );
				
				# Push any included files onto the file list and undef for next round
				if( exists $self->{v}{statistics}{Include} ) {
					my @f = ($self->{v}{statistics}{Include});
					@f = @{$f[0]} if ref($f[0]) eq 'ARRAY';
					push @files, @f;
					delete $self->{v}{statistics}{Include};
				} # end if
			} # end foreach
		} # end if
	} # end unless
	

	# Make sure all the settings are recognized
	$self->_recognize_all();

	# Clean up the settings
	$self->_conversions();
	$self->_defaults();
	$self->_sanity_checks();

	return $self;
} # end TIEHASH
   




     
##########################
##                      ##
##    Public Methods    ##
##                      ##
##########################


# ----------------------------------------------------------
# Sub: getFilename
#
# Args: (None)
#
# Description: Returns the filename for the user settings file
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Mar21 Created the function                          JW
# ----------------------------------------------------------
sub getFilename {
	my $self = shift;
	return $self->{FILENAME};
} # end getFilename



# ----------------------------------------------------------
# Sub: get_styles
#
# Args: $section
#	$section	The section (report or navigation) for which to 
#           parse settings from
#
# Description: Parses settings from a section of the settings
# into a css style sheet.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May26 Created method                                JW
# 2000Dec01 Now quotes font family names with whitespace  JW
# ----------------------------------------------------------
sub get_styles {
	my $self = shift;
	my( $section, $group, $elm ) = @_;
	$elm = 'body' unless defined $elm && $elm;
	
	if( defined $group && $group ) {
		$group .= '_';
	} else {
		$group = '';
	} # end if
	
	$self->newval( $section, '_styles', {} ) unless $self->val( $section, '_styles' );
	my $styles = $self->val( $section, '_styles' );
	$styles->{$elm} = {} unless defined $styles->{$elm};
	
	if( $self->val( $section, $group . 'Font' ) ) {
		# Make sure all elements with spaces are quoted
		my @families = split /\s*,\s/, $self->val( $section, $group . 'Font' );
		foreach (@families) {
			$_ = "\"$_\"" if /\s/ & !/\"/;
		} # end foreach
		$styles->{$elm}{'font-family'} = join ',', @families;
	} # end if
	if( $self->val( $section, $group . 'Font_Color' ) ) {
		$styles->{$elm}{color} = $self->val( $section, $group . 'Font_Color' );
	} # end if
	if( $self->val( $section, $group . 'Background' ) ) {
		$styles->{$elm}{'background-image'} = 'url(' . $self->val( $section, $group . 'Background' ) . ')';
	} # end if
	if( $self->val( $section, $group . 'BG_Color' ) ) {
		$styles->{$elm}{'background-color'} = $self->val( $section, $group . 'BG_Color' );
	} # end if

	return;
} # end get_styles

        
# ----------------------------------------------------------
# Sub: get_report_styles
#
# Args: $section
#	$section	The section (report letter) to get styles for
#
# Description: Convenince method to create a stylesheet for
# a given report.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May26 Created method                                JW
# 2000Oct03 Added check for Stylesheet attribute          JW
# ----------------------------------------------------------
sub get_report_styles {
	my $self = shift;
	my $section = shift || 'reports';
	
	# Don't set any default styles if there's a stylesheet present.
	return if $self->val( $section, 'Stylesheet' );
	
	$self->newval( $section, '_styles', {} ) unless $self->val( $section, '_styles' );
	my $styles = $self->val( $section, '_styles' );

	# Setup the style sheet for the Report pages
	$self->get_styles( $section );	

	# Duplicate the body element into p and td for Netscape
	$styles->{p} = {} unless defined $styles->{p} && ref($styles->{p}) eq 'HASH'; 
	$styles->{td} = {} unless defined $styles->{td} && ref($styles->{td}) eq 'HASH'; 
	%{$styles->{p}} = %{$styles->{body}};
	%{$styles->{td}} = %{$styles->{td}};

	$styles->{h1} = {} unless defined $styles->{h1};
	$styles->{h1}{'font-size'} = '20pt';
	$styles->{h1}{'text-align'} = 'CENTER';

	# Setup some defaults for the 'h2' style, then build styles from settings
	$styles->{h2} = {} unless defined $styles->{h2};
	$styles->{h2}{'font-size'} = '12pt';
	if( defined $self->val( $section, 'Title_BG_Color' ) ) {
		$styles->{h2}{width} = '95%';
		$styles->{h2}{padding} = '3pt';
		$styles->{h2}{border} = 'none';
		$styles->{h2}{'font-weight'} = 'bold';
	} # end if
	$self->get_styles( $section, 'Title', 'h2' );	

	$styles->{'.fineprint'} = {} unless defined $styles->{'.fineprint'};
	$styles->{'.fineprint'}{'font-size'} = '7pt';
	$styles->{'.smallfont'} = {} unless defined $styles->{'.smallfont'};
	$styles->{'.smallfont'}{'font-size'} = '8pt';

	if( $self->val( $section, 'Data_Font' ) ) {
		$styles->{td} = {} unless defined $styles->{td};
		$styles->{'td'}{'font-family'} = $self->val( $section, 'Data_Font' );
	} # end if
	if( $self->val( $section, 'Data_Font_Color_1' ) ) {
		$styles->{'td.alt1'} = {} unless defined $styles->{'td.alt1'};
		$styles->{'td.alt1'}{color} = $self->val( $section, 'Data_Font_Color_1' );
	} # end if
	if( $self->val( $section, 'Data_Font_Color_2' ) ) {
		$styles->{'td.alt2'} = {} unless defined $styles->{'td.alt2'};
		$styles->{'td.alt2'}{color} = $self->val( $section, 'Data_Font_Color_2' );
	} # end if
	if( $self->val( $section, 'Data_BG_Color_1' ) ) {
		$styles->{'td.alt1'} = {} unless defined $styles->{'td.alt1'};
		$styles->{'td.alt1'}{'background-color'} = $self->val( $section, 'Data_BG_Color_1' );
	} # end if
	if( $self->val( $section, 'Data_BG_Color_2' ) ) {
		$styles->{'td.alt2'} = {} unless defined $styles->{'td.alt2'};
		$styles->{'td.alt2'}{'background-color'} = $self->val( $section, 'Data_BG_Color_2' );
	} # end if

	$self->get_styles( $section, 'Data_Header', 'th' );	

	$self->get_styles( $section, 'Data_Total', 'th.total' );	

	return $self;
} # end get_report_styles


# ----------------------------------------------------------
# Sub: get_nav_styles
#
# Args: (None)
#
# Description: Convenience method to retrieve all the styles 
# and set defaults necessary for the Navigation stylesheet
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May26 Created method                                JW
# 2000Oct03 Added check for Stylesheet attribute          JW
# 19Aug2002 Added navbullet class for no italic on hover  JW
# ----------------------------------------------------------
sub get_nav_styles {
	my $self = shift;

	# Don't set any default styles if there's a stylesheet present.
	return if $self->val( 'navigation', 'Stylesheet' );
	
	$self->newval( 'navigation', '_styles', {} ) unless $self->val( 'navigation', '_styles' );
	my $styles = $self->val( 'navigation', '_styles' );

	# Setup the style sheet for the Navigation panel
	$self->get_styles( 'navigation' );	

	$styles->{body} = {} unless defined $styles->{body};
	$styles->{body}{'font-size'} = '9pt';
	$styles->{td} = {} unless defined $styles->{body};
	$styles->{td}{'font-size'} = '9pt';
	$styles->{h4} = {} unless defined $styles->{h4};
	$styles->{h4}{'font-size'} = '12pt';
	
	$styles->{a} = {} unless defined $styles->{a};
	$styles->{a}{'font-weight'} = 'normal';
	$styles->{a}{'text-decoration'} = 'none';
	if( $self->val( 'navigation', 'Font_Color' ) ) {
		$styles->{'a:link'} = {} unless defined $styles->{'a:link'};
		$styles->{'a:visited'} = {} unless defined $styles->{'a:visited'};
		$styles->{'a:active'} = {} unless defined $styles->{'a:active'};
		$styles->{'a:link'}{color} = $self->val( 'navigation', 'Font_Color' );
		$styles->{'a:visited'}{color} = $self->val( 'navigation', 'Font_Color' );
		$styles->{'a:active'}{color} = $self->val( 'navigation', 'Font_Color' );
	} # end if
	$styles->{'a:hover'} = {} unless defined $styles->{'a:hover'};
	$styles->{'a:hover'}{'font-style'} = 'italic';
	$styles->{'.navbullet a:hover'}{'font-style'} = 'normal';

	return $self;
} # end get_nav_styles



##########################
##                      ##
##   Private Methods    ##
##                      ##
##########################


# ----------------------------------------------------------
# Sub: _parse_command_line
#
# Args: @args
#	@args	A list of command-line arguments to the program
#
# Returns: The name of the file parsed for settings.
#          Settings are stored in $settings->{config}
#
# Description: Parses command-line arguments for filename 
#              and overrides and builds a hash of settings
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Mar29 Added support for commandline filename        JW
# 1999Aug21 Added suprort for command-line overrides      JW
# 2000May26 Pulled out defaults, conversion and sanities  JW
# 2000May26 Converted to command-line parser              JW
# 2000Jun14 Fixed processing for new data model           JW
# 04Feb2003 Added short-circuit options (help, etc.)      JW
# ----------------------------------------------------------
sub _parse_command_line {
	my $self = shift;
	my $filename = undef;
	my @args = @_;
	
	foreach ( @args ) {
		if( /^--?(.+)/ ) {
			# Parse '-option' arguments
			my $name = $1;
			my $val = 1;
			if( $name =~ /([^=]+)=(.+)/ ) {
				$name = $1;
				$val = $2;
			} # end if
			if( $name =~ /(_*[^_-]+)[_-](.+)/ ) {
				$name = $1;
				my $name2 = $2;
				$name2 =~ s/-/_/g;
			#** $self->newsection( $name ) unless defined $self->Parameters( $name );
				if( defined $self->val( $name, $name2 ) ) {
					$self->setval( $name, $name2, $val );
				} else {
					$self->newval( $name, $name2, $val );
				} # end if
			} elsif ( $name =~ /^h(elp)?$|^\?$/i ) {
				$0 =~ s(^.+[\\/])();
				print $self->{version};
				print
qq[
Basic Usage:
$0 [options] rmagic.ini

  'rmagic.ini' is the name of a settings file to use

Some valid options include
  -h  --help       Show this message
  -v  --version    Show the version
      --settings   Write out settings from the current configuration
  
HTML documentation is in the docs folder, starting with index.html.
Please read the License.html file for terms and conditions.
You can also find documentation online at http://reportmagic.org/
];
				exit;
			} elsif ( lc($name) eq 'v' || lc($name) eq 'version' ) {
				print $self->{version};
				exit;
			} elsif ( lc($name) eq 'settings' ) {
				# Just use Config::IniFiles' OutputConfig method to write 
				# it all to STDOUT, including comments! Weee!
				$self->OutputConfig();
				exit;
			} else {
				# Invalid command line argument
				wadg::Errors::warning( 'W0006', $name );
			} # end if
		} # end if
	} # end for

} # end _parse_command_line



# ----------------------------------------------------------
# Sub: _sanity_check
#
# Args: (None)
#
# Description: Runs some sanity checks on the settings and 
# forces some values based on others.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr04 Fixed bug in declarations like my( undef, ... JW
# 2000May26 Created from sections of _read_user_settings  JW
# 2000Nov29 One_File test with -d; now makes proper paths JW
# 2001Feb06 Changed directory test, cause it failed       JW
# 06Feb2003 Added [graphs] Path_To and URL_To cleaning    JW
# 21Mar2003 Better guessing of paths without trailing /   JW
# ----------------------------------------------------------
sub _sanity_checks {
	my $self = shift;

	# 
	# Get the output directory for all the output files and 
	# force them into that directory
	#
	
	my $outDir = $self->val( 'reports', 'File_Out' );

	#
	# Set statistics_One_File based on what the output file is
	# If the file does not already exists as a directory, then get
	# the directory portion with fileparse. Don't use dirname, because
	# on Unix and DOS/Windows it will make something like 'lib/' have 
	# a directory part of '.' -- cruft.
	#
	if( !-e $outDir || !-d $outDir ) {
		(undef, $outDir, undef) = fileparse( $self->val( 'reports', 'File_Out' ) );
	} # end if

	#
	# If the $outDir matches exaclty the directory component then it's a directory
	#
	if( $outDir eq  $self->val( 'reports', 'File_Out' ) ) {
		$self->newval( 'statistics', 'One_File', 0 );
	} else {
		$self->newval( 'statistics', 'One_File', 1 );
	} # end if

	#
	# Put the navigation and frameset files in the same folder as the reports
	#
	if( $self->val( 'navigation', 'File_Out' ) && 
	    $self->val( 'navigation', 'File_Out' ) !~ /^(LEFT|TOP|RIGHT|BOTTOM|NONE)$/i ) {;
		$self->setval( 'navigation', 'File_Out', File::Spec->catfile( $outDir, basename( $self->val( 'navigation', 'File_Out' ) ) ) );
	} # end if
	if( defined $self->val( 'statistics', 'Frame_File_Out' ) ) {
		$self->setval( 'statistics', 'Frame_File_Out', File::Spec->catfile( $outDir, basename( $self->val( 'statistics', 'Frame_File_Out' ) ) ) );
	} # end if

	#
	# Drop any any last '/' or '\' on website_Base_URL
	#
	my $website = $self->val( 'website', 'Base_URL' );
	if( $website =~ s/^(.*)[\/\\]$/$1/ ) {
		$self->setval( 'website', 'Base_URL', $website );
	} # end if

	#
	# Make sure there's a terminating '/' on graphs_URL_To
	# Do opposite for the Path_To, using portable code
	#
	my $url_to = $self->val( 'graphs', 'URL_To' );
	if( defined($url_to) && $url_to !~ m[/$] ) {
		$self->setval( 'graphs', 'URL_To', "$url_to/" );
	} # end if
	my $path_to = $self->val( 'graphs', 'Path_To' );
	if( defined $path_to ) {
		$self->setval( 'graphs', 'Path_To', File::Spec->canonpath( $path_to ) );
	} # end if

	#
	# Make Active Column a useful value
	#
	if( defined $self->val( 'reports', 'Active_Column' ) ) {
		# Make sure it's only the first letter.
		my $ac = substr( $self->val( 'reports', 'Active_Column' ), 0, 1 );
		# Add "_" indicator to capital columns
		$ac .= '_' if $ac eq uc($ac);
		$self->setval( 'reports', 'Active_Column', $ac );
	}  # end if

	# If outputting to STDOUT, then force non-frames mode and 
	# one-file mode and turn off Quick Summary (STDOUT cannot 
	# be reopend to insert the summary). No notices either.
	if( $self->val( 'reports', 'File_Out' ) eq '-' ) {
		$self->setval( 'navigation', 'File_Out', 'RIGHT' ) unless $self->val( 'navigation', 'File_Out' ) =~ /^(LEFT|TOP|RIGHT|BOTTOM)$/i;
		$self->setval( 'statistics', 'One_File', 1 );
		$self->delval( 'q', 'Rows' );
		my $v = $self->val( 'statistics', 'Verbose' );
		$v =~ s/N//;
		$self->setval( 'statistics', 'Verbose', $v );
	} # end if

	# Don't allow [statistics]File_In to contain %infile% or ${infile}
	my $infile = $self->val( 'statistics' , 'File_In' );
	$infile	=~ s/%infile%//i;
	$infile	=~ s/\$\{infile\}//i;
	$self->setval( 'statistics' , 'File_In', $infile );

	return $self;
} # end _sanity_checks




# ----------------------------------------------------------
# Sub: _conversions
#
# Args: (None)
#
# Description: Converts settings from old styles to current one
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May26 Created from sections of _read_user_settings  JW
# 2000Jun14 Implemented __convert method for clarity      JW
# 20Feb2003 Patched so Language=no was not changed to 0   JW
# ----------------------------------------------------------
sub _conversions {
	my $self = shift;

	# Title moved from [reports] to [website]
	$self->__convert( 'website', 'Title', 'reports', 'Title' );

	# Active_Column moved from [statistics] to [reports]
	$self->__convert( 'reports', 'Active_Column', 'statistics', 'Active_Column' );

	# Graph_Font moved from [reports] to [graphs]Font
	$self->__convert( 'graphs', 'Font', 'reports', 'Graph_Font' );

	# Image_ball changed to Bullet_Image
	$self->__convert( 'navigation', 'Bullet_Image', 'navigation', 'Image_Ball' );

	# Reverse_Time moved from [statistics] to [reports]
	$self->__convert( 'reports', 'Reverse_Time', 'statistics', 'Reverse_Time' );

	# Update names of nav page styles
	$self->__convert( 'navigation', 'Font', 'navigation', 'Page_Font' );
	$self->__convert( 'navigation', 'Font_Color', 'navigation', 'Page_Font_Color' );
	$self->__convert( 'navigation', 'BG_Color', 'navigation', 'Page_BG_Color' );
	$self->__convert( 'navigation', 'Background', 'navigation', 'Page_Background' );

	# Update names of "_Color" to "_BG_Color"
	$self->__convert( 'reports', 'Data_BG_Color_1', 'reports', 'Data_Color_1' );
	$self->__convert( 'reports', 'Data_BG_Color_2', 'reports', 'Data_Color_2' );
	$self->__convert( 'reports', 'Data_Header_BG_Color', 'reports', 'Data_Header_Color' );
	$self->__convert( 'reports', 'Data_Total_BG_Color', 'reports', 'Data_Total_Color' );

	# Move "General_Rows" and "Summary_Rows" to their own sections
	$self->__convert( 'statistics', 'General_Rows', 'x', 'Rows' );
	$self->__convert( 'statistics', 'Summary_Rows', 'q', 'Rows' );

	# Equivalent boolean keywords
	my( $S, $P );
	foreach $S ( $self->Sections() ) {
		foreach $P ( $self->Parameters( $S ) ) {
			next unless defined $self->val( $S, $P );
			next if $P eq 'Language';		# May need to preserve other than just "no" language
			$self->setval( $S, $P, 1 ) if $self->val( $S, $P ) =~ /^(YES|ON|TRUE)$/i;
			$self->setval( $S, $P, 0 ) if $self->val( $S, $P ) =~ /^(NO|OFF|FALSE|NONE)$/i;
		} # end foreach
	} # end foreach
	
	return $self;
} # end _conversions



# ----------------------------------------------------------
# Sub: __convert
#
# Args: $new_section, $new_parm, $old_section, $old_parm
#
# Description: Helper method to convert settings from one
# area to method
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Jun14 Created function                              JW
# ----------------------------------------------------------
sub __convert {
	my $self = shift;
	my( $new_section, $new_parm, $old_section, $old_parm ) = @_;
	
	unless( defined $self->val( $new_section, $new_parm ) ) {
		$self->newval( $new_section, $new_parm, $self->val( $old_section, $old_parm ) );
	} # end if
} # end __convert



# ----------------------------------------------------------
# Sub: _defaults
#
# Args: (None)
#
# Description: Sets default values for some elements
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May26 Created from sections of _read_user_settings  JW
# 2000Oct17 Fixed bug in ALL setting in GENERAL section   JW
# 2000Nov28 Added default for Graph_Level setting         JW
# 06Feb2003 Added default File_Extension                  JW
# 14Feb2003 Default Frameset is index.html                JW
# 10Mar2003 Default input and output to STDIN/STDOUT      JW
# ----------------------------------------------------------
sub _defaults {
	my $self = shift;
	
	#	
	# Check GD for support of desired output format. If none
	# given or not capable, then set output format accordingly.
	#
	my $g = new GD::Image(0,0);

	if( defined $self->val( 'graphs', 'Format' ) ) {
		if( $self->val( 'graphs', 'Format' ) =~ /jpe?g/i ) {
			$self->setval( 'graphs', 'Format', 'jpeg' );
		} else {
			$self->setval( 'graphs', 'Format', lc($self->val( 'graphs', 'Format' )) );
		} # end if
		unless( $g->can( $self->val( 'graphs', 'Format' ) ) ) {
			if( $g->can( 'png' ) ) {
				$self->setval( 'graphs', 'Format', 'png' );
			} elsif( $g->can( 'gif' ) ) {
				$self->setval( 'graphs', 'Format', 'gif' );
			} elsif( $g->can( 'jpeg' ) ) {
				$self->setval( 'graphs', 'Format', 'jpeg' );
			} # end if
		} # end if
	} else {
		if( $g->can( 'png' ) ) {
			$self->newval( 'graphs', 'Format', 'png' );
		} elsif( $g->can( 'gif' ) ) {
			$self->newval( 'graphs', 'Format', 'gif' );
		} elsif( $g->can( 'jpeg' ) ) {
			$self->newval( 'graphs', 'Format', 'jpeg' );
		} # end if
	} # end if
	
	# -- If format is still not defined, then error:
	unless( defined $self->val( 'graphs', 'Format' ) ) {
		wadg::Errors::error( -1, 'E0015', 'dgsupport\@wadsack-allen.com', $GD::VERSION, $self->val( '_INTERNAL', '_VERSION' ) );
	} # end unless

	# -- Default vebosity is all
	if( !defined $self->val( 'statistics', 'Verbose' ) ) {
		$self->newval( 'statistics', 'Verbose', 'NWE' );
	} elsif( $self->val( 'statistics', 'Verbose' ) =~ /NONE/i ) {
		$self->setval( 'statistics', 'Verbose', '' );
	} # end if

	# -- Make General Summary and Quick Summary ROWS defaults
	{ # Scope block
		my $general = $self->val( 'x', 'Rows' ) || $self->val( 'GENERAL', 'Rows' ) || '';
		my $quick = $self->val( 'q', 'Rows' ) || $self->val( 'QUICK', 'Rows' ) || '';
		$self->newval( 'x', 'Rows', '' ) unless $general;
		$self->setval( 'x', 'Rows', '' ) if $general =~ /ALL/i || $general =~ /ALL/i;
		$self->delval( 'GENERAL', 'Rows' ) if $general =~ /ALL/i;
		if( $quick =~ /NONE/i ) {
			$self->delval( 'q', 'Rows' );
			$self->delval( 'QUICK', 'Rows' );
		} # end if
	} # end scope

	# -- Default Navigation Position is RIGHT
	if( defined $self->val( 'navigation', 'File_Out' ) ) {
		$self->setval( 'navigation', 'File_Out', 'RIGHT') if $self->val( 'navigation', 'File_Out' ) eq $self->val( 'reports', 'File_Out' );
	} else {
		# Since 'reports' is default, this case really never happens. 
		# So maybe this should be an assert? [JW]
		$self->newval( 'navigation', 'File_Out', 'RIGHT');
	} # end if
	$self->delval( 'navigation', 'File_Out' ) if $self->val( 'navigation', 'File_Out' ) =~ /NONE/i;
	
	
	# -- Default File_In and File_Out are STDIN and STDOUT respectively
	$self->newval( 'reports', 'File_Out', '-') unless defined $self->val( 'reports', 'File_Out' );
	$self->newval( 'statistics', 'File_In', '-') unless defined $self->val( 'statistics', 'File_In' );


	# -- Deafault Graph_Level is 1
	$self->newval( 'reports', 'Graph_Level', '1') unless defined $self->val( 'reports', 'Graph_Level' );

	# -- Default File_Extension is .html
	$self->newval( 'reports', 'File_Extension', '.html') unless defined $self->val( 'reports', 'File_Extension' );
	
	# -- Default Frame_File_Out is index.{File_Extension}
	#    Therefore this must be done after the default file extension is set
	$self->newval( 'statistics', 'Frame_File_Out', 'index' . $self->val( 'reports', 'File_Extension' ) ) unless defined $self->val( 'statistics', 'Frame_File_Out' );
	
	
	########
	# NOTE: Default values for [CGI] Forbidden and Analog_Forbidden are set in teh 
	#       CGI section, because they need to be known before reading the CGI input
	########
	
	
	return $self;
} # end _defaults




# ----------------------------------------------------------
# Sub: _recognize_all
#
# Args: $section, $parameter
#
# Description: Returns true if every current setting passes
# the test in _recognize method
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 04Feb2003 Added method to reduce spelling problems      JW
# 06Feb2003 Changed to a hash-lookup for speed            JW
# 25Mar2003 Converted to __DATA sub for Windows binary    JW
# ----------------------------------------------------------
sub _recognize_all {
	my $self = shift;
	my( $filename ) = @_;
	my( $S, $P );
	
	
	#
	# Load the KNOWN_SETTINGS hash if it's not loaded
	#
	# We use a hash to store both section AND param names
	# because a hash lookup is MUCH faster than a list grep
	# There are examples of this in Camel, Cookbook and List::Compare
	#
	unless( %KNOWN_SETTINGS ) {
		my $cur = '';
		foreach( split( /\n/, &__DATA() ) ) {
			chomp;
			if( /\[([^\]]+)\]/ ) {
				$cur = $1;
				next unless defined $cur;
				$KNOWN_SETTINGS{$cur} = {} unless exists $KNOWN_SETTINGS{$cur};
			} else {
				$KNOWN_SETTINGS{$cur}{$_}++;
			} # end if
		} # end foreach
	} # end unless

	#
	# Now build %KNOWN_REPORTS hash from list
	#
	if( @KNOWN_REPORTS && !%KNOWN_REPORTS ) {
		foreach( @KNOWN_REPORTS ) {
			$KNOWN_REPORTS{$_}++;
		} # end foreach
	} # end unless
	
	
	
	#
	# Run through the sections and parameters and 
	# make sure all are valid
	#
	for $S ( $self->Sections() ) {
		
		# Ignore empty sections (bug in some versions of Config-IniFiles)
		next unless defined $S;
		
		for $P ( $self->Parameters( $S ) ) {
			
			# Ignore empty parameters (bug in some versions of Config-IniFiles)
			next unless defined $P;

			# If the $section part is one of the defaults then check normally
			if( $KNOWN_SETTINGS{$S} ) {
				unless( $KNOWN_SETTINGS{$S}{$P} ) {
					wadg::Errors::warning( 'W0008', "[$S] $P" );
				} # end if
				next;
			} # end if
			
			# If it's not a regular section, then it should be a report name
			unless( $KNOWN_REPORTS{$S} ) {
				wadg::Errors::warning( 'W0008', "[$S] $P" );
				next;
			} # end if
			
			# If it's a report name section, then make sure the parameter is part of [reports]
			unless( $KNOWN_SETTINGS{reports}{$P} ) {
				wadg::Errors::warning( 'W0008', "[$S] $P" );
				next;		# Not needed... but...
			} # end if

		} # end for
	} # end for
	
	return 1;
} # end _recognize_all





# ----------------------------------------------------------
# Sub: _include_file
#
# Args: %param
#
# Description: Adds the settings in $param{-file} to the 
# current settings
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 06Feb2003 Added method to support mutliple includes     JW
# 27Feb2003 Added safety check for _INTERNAL settings     JW
# ----------------------------------------------------------
sub _include_file {
	my $self = shift;
	my( %parms ) = @_;

	#
	# Load a config file using the 
	# given parameters
	#
	my $inc = new Config::IniFiles( %parms );

	#
	# Now put these settings on top of the other ones
	#
	my( $S, $P );
	foreach $S ( $inc->Sections() ) {
		
		# Don't allow importing of _INTERNAL values
		next if $S eq '_INTERNAL';		
	
		foreach $P ( $inc->Parameters( $S ) ) {
	
			unless( exists $self->{v}{$S}{$P} ) {
		
				my( @A ) = $inc->val( $S, $P );
				if( @A > 1 ) {
					$self->{v}{$S}{$P} = \@A;
				} else {
					$self->{v}{$S}{$P} = $A[0];
				} # end if
		
			} # end unless
	
		} # end foreach
	
	} # end foreach
	
} # end _include_file




# ----------------------------------------------------------
# Sub: _analog_printargs
#
# Args: $query, $cgi_arg [, $config_arg]
#
# Description: Returns a line for the Analog configuration
# made up of the argument and it's value, properly normalized
# and checked for CGI-safety
#
# Based on printargs sub in Analog's anlgform.pl
# Copyright 1995 - 2002 Stephen R. E. Turner
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 09Mar2003 Modified to make a method                     JW
# ----------------------------------------------------------
sub _analog_printargs {
	my $self = shift;
	my $query = shift;
	my($name) = $_[1] || $_[0];

	my($is_floora) = 0;
	my($is_12) = 0;
	my $config = '';
	
	if ($name =~ /FLOORA$/) {
		chop($name);
		$is_floora = 1;
	} elsif ($name =~ /1$/) {
		chop($name);
		$is_12 = 1;
	} # end if
	
	if ($is_floora) {
		my $a = $query->param($name . 'A');  # last "FLOORA=$a" form arg specified
		my $b = $query->param($name . 'B');
		$config = "$name $a$b" if ($b ne '' && $b !~ /\\$/);
		# could bracket $a$b, but no help because any special character in a
		# FLOOR command is junk anyway.
	} elsif ($is_12) {
		my $a = $query->param($name . '1');
		my $b = $query->param($name . '2');
		$config =  ("$name " . _analog_backet($a) . " " . _analog_backet($b)) if ($b ne '');
	} else {
		my $a;
		foreach $a ( $query->param($_[0]) ) {  # run through all "NAME=$a" form args
			if ($a ne '') {
				$config .= "$name " . _analog_backet($a);
				$config .= ("DNS READ") if ($name eq 'DNSFILE');
			} # end if
		} # end foreach
	} # end if

	# Make sure that the characters are valid, or dump it
	return '' if $config =~ /[\x00-\x1F\x7F-\x9F]/;
	if( $name =~ /LOGFILE/ or $name =~ /CACHEFILE/ ) {
		return '' if $config =~ m([^\w. /\\:\-*?]) || $config =~ m(\B-|-\B);
	} # end if
	
	return $config;
} # end _analog_printargs



# ----------------------------------------------------------
# Sub: _analog_backet
#
# Args: $value
#
# Description: Returns the value enclosed in single quotes,
# double quotes or parentheses.
#
# Based on bracket sub in Analog's anlgform.pl
# Copyright 1995 - 2002 Stephen R. E. Turner
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# ----------------------------------------------------------
sub _analog_backet {
    local $_ = $_[0];
    return $_ unless (/[\s\#]/ || /^['"\(]/ || /\\$/);
    return "\"$_\"" unless (/"/);
    return "'$_'" unless (/'/);
    return "($_)";
} # end _analog_backet



# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds


#----------------------------------------------------------------------
# The DATA section below is be used for a basic "known settings" check
# NOTE: In compiled version for Windows, we can't user the 'DATA' section
# because the ActiveState compiler doesn't know how to get to it. So instead
# We''l just make this a function that returns a scalar and parse it above.
#----------------------------------------------------------------------
sub __DATA {
return q{
[_INTERNAL]
_VERSION
_TITLE
_CGI
[reports]
File_Out
Active_Column
Meta_Refresh
Image_Dir
Stylesheet
Reverse_Time
Graph_Level
BG_Color
Background
Font
Font_Color
Title_Font
Title_BG_Color
Title_Font_Color
Data_Font
Data_Font_Color
Data_Font_Color_1
Data_Color_1
Data_BG_Color_1
Data_Font_Color_2
Data_Color_2
Data_BG_Color_2
Data_Total_Font
Data_Total_Font_Color
Data_Total_BG_Color
Data_Total_Color
Data_Header_Font
Data_Header_Font_Color
Data_Header_BG_Color
Data_Header_Color
Width
Height
3d
Show_Bytes_As
Rows
File_Extension
ShortName
LongName
DataName
ReportType
Truncate
IncludeLinks
SmallFont
TimeFormat
GraphType
MostActive
Average
Summary1
Summary2
Description
[graphs]
BG_Color
Font
Font_Color
Width
Height
3d
Palette
Cycle_Colors
Shadows
Format
Path_To
URL_To
[statistics]
File_In
Frame_File_Out
Frame_Border
Reverse_Time
No_Robots
Log_File
Always_Quit
Language
Verbose
Include
Format
[navigation]
File_Out
BG_Color
Background
Font_Color
Font
Bullet_Image
Stylesheet
Top_Logo
[website]
Title
Webmaster
Base_URL
Company_Logo
[CGI]
Analog
Analog_Config
Analog_Forbidden
Analog_Allowed
Forbidden
Allowed
};
} # end _DATA
