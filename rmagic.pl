#!/usr/bin/perl
###################################################################
# Report Magic
#
# A statistics presentation tool used to build readable reports
# from web server log file analyses produces by Analog. For 
# complete information see the documentation starting at 
# docs/index.html in the distribution.
#
# Merged & re-written: 1999.Feb.19 by Jeremy Wadsack, for Wadsack-Allen Digital Group
# 	Copyright (C) 1999,2002 Wadsack-Allen. All rights reserved. 
#  http://www.wadsack-allen.com/digitalgroup/
#
# Original concept: 1999 by Corey Kaye, for Digital Nova Scotia
# 	Copyright (C) 1999 Digital Nova Scotia. All rights reserved.
#  http://www.digitalns.pair.com/
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the Artistic License as described in 
# docs/license.html
###################################################################
# Date        Modification
# -----------------------------------------------------------------
# * SEE What's New AND Changes IN THE DOCUMENTATION *
###################################################################
require 5.004;
use strict;

# Some debugging aids
my $RealBin;		# Global for use later...
BEGIN {
	if( 0 ) {
		$SIG{__WARN__} = sub { 
			warn $_[0]; 
			my @fields = caller(0);
			print STDERR "Stack trace: ";
			print STDERR "called from $fields[1] line $fields[2]" unless $_[0] =~ /\n$/;
			print STDERR "\n";
			for( 1 .. 100 ) {
				@fields = caller($_);
				last unless @fields;
				print STDERR "             $fields[3] in $fields[1] line $fields[2]\n";
			} # end for
		};
	} # end if
	
	# Portably handle File routines
	use File::Copy;
	use File::Basename;
	use File::Path;
	
	# - Find execution directory
	#   This will fail if it is in a directory where it doesn't have access
	#   all the way to to root. If this is the case, then fall back to using 
	#   relative paths.
	eval( 'require FindBin' );
	if( $@ || ! $FindBin::RealBin) {
		print $@;
		# Copied from FindBin.pm
		my $script = $0;
	
		# Workaround for Win32 not finding 'rmagic' when looking for 'rmagic.exe'
		my $IsWin32 = $^O eq 'MSWin32';
		if( $IsWin32 && $script !~ m!\.[^\.]+$! ) {
			$script .= '.exe' if -e "$script.exe";
		} # end if
		
		# Rest from FindBin.pm
		if ($^O eq 'VMS') {
			my ($Bin,$Script) = VMS::Filespec::rmsexpand($0) =~ /(.*\])(.*)/s;
			$RealBin = $Bin;
		} else {
			unless( ($script =~ m!/! || ($IsWin32 && $script =~ m!\\!)) && -f $script ) {
				my $dir;
				foreach $dir (File::Spec->path) {
					my $scr = File::Spec->catfile($dir, $script);
					if( -r $scr && (!$IsWin32 || -x _) ) {
						$script = $scr;
						$script = $0 if -f $0 && (!-T $script);
						last;
					} # end if
				} # end foreach
			} # end unless
			die("Cannot find current script '$0'") unless(-f $script);
			my($Script,$Bin) = fileparse($script);
			$RealBin = $Bin;
		} # end if
	} else {
		$RealBin = $FindBin::RealBin;
	} # end if
	$RealBin = "." unless $RealBin;

} # end BEGIN


#-------------------------------#
# Setup which libraries we need #
#-------------------------------#

# If you're running Perl 5.004 you'll need to get this from CPAN, 
# it ships with 5.005 and 5.6
use File::Spec;


# - Add execution directory to lib path, resolving symbolic refs
use lib $RealBin;

# - Read INI files
use Config::IniFiles;

# - Our own internal libraries (ship with software)
use wadg::Formatter;
use wadg::Errors;
use wadg::HTMLWriter;
use wadg::rm::Settings;
use wadg::rm::CROParser;
use wadg::rm::Graphs;
use wadg::rm::Report;
	use wadg::rm::Report::GeneralSummary;
	use wadg::rm::Report::TimeReport;
	use wadg::rm::Report::TimeSummary;
	use wadg::rm::Report::HierarchicalReport;
	use wadg::rm::Report::RangeReport;
	use wadg::rm::Report::QuickSummary;

#-------------------------------#
# Declare our global variables  #
#-------------------------------#
my %config;
	$config{_INTERNAL} = ();
	$config{_INTERNAL}{'_TITLE'} = 'Report Magic';
	$config{_INTERNAL}{'_VERSION'} = '2.21';

my( $rdata, $cdata, $lang );
my $logFile = *STDERR;	
my %statistics;
my %navigation;
my( $HEADER, $PREFIX, $HEADER_USED ) = (
	"$config{_INTERNAL}{_TITLE} $config{_INTERNAL}{_VERSION}\nCopyright (C) 1999-2003 Wadsack-Allen. All rights reserved.\n",
	'rmagic: ',
	0
);


#-------------------------------------#
# CGI detection and initialization    #
#-------------------------------------#
if( exists $ENV{'REQUEST_METHOD'} ) {
	# -- Set CGI mode for everything else to respond to
	$config{_INTERNAL}{_CGI} = 'CGI';
	
	# -- Use CGI module to read our parameters
	#    NOTE: This is redundant (it's done in Settings.pm) but
	#    by putting here, we can run-time error right away
	require CGI;
	
	# -- Send out the CGI header right now.
	#    Do this by hand, because if we instantiate a CGI 
	#    object here, we will consume STDIN (for POST) thus
	#    making it impossible to get later in Settings.pm
	print STDOUT "Content-type: text/html\n";
	# NOTE we could add other headers here, e.g. no-cache
	print STDOUT "\n";
	
} # end if


#-------------------------------------#
# Build our objects and configuration #
#-------------------------------------#
my $formatter = new wadg::Formatter();
my $croParser = new wadg::rm::CROParser;
   $croParser->{globals}{'NAME'} = $config{_INTERNAL}{_TITLE};
   $croParser->{globals}{'VERSION'} = $config{_INTERNAL}{_VERSION};

#
#  Load the English language message file for default error messages
#
$lang = new Config::IniFiles( 
	-file => File::Spec->catfile( $RealBin, 'lang', 'en', 'lang.ini' ),
);
if( !defined $lang ) {
	# Can't use message function if $lang is undefined so just print these notices
	print $HEADER;
	print "\nERROR: Language file " . File::Spec->catfile( $RealBin, 'lang', 'en', 'lang.ini' ) . " is missing or corrupt.\n\n";
	&finalize( -1 );
} # end if


# - Register our exception handlers now that language is loaded
wadg::Errors::set_warning_handler( \&message );
wadg::Errors::set_error_handler( \&finalize );


# -- Get the rest of the root 'language' files (to load settings)
$rdata = new Config::IniFiles( 
	-file => File::Spec->catfile( $RealBin, 'lang', '.root', 'rdata.ini' ),
);
if( !defined $rdata || !$rdata->Sections ) {
	warn $rdata;
	wadg::Errors::error( -1, 'E0011', File::Spec->catfile( $RealBin, 'lang', '.root', 'rdata.ini' ) );
} # end if

$cdata = new Config::IniFiles(
	-file => File::Spec->catfile( $RealBin, 'lang', '.root', 'cdata.ini' ),
);
if( !defined $cdata || !$cdata->Sections ) {
	warn $!;
	wadg::Errors::error( -1, 'E0011', File::Spec->catfile( $RealBin, 'lang', '.root', 'cdata.ini' ) );
} # end if

#
# Store the report-names list into the package variable
# So that we can look them up when we read the settings file
## Yes, this really is an ugly hack! And we end up doing short-name lookups twice!
#
{ # scope for variables
	my( $S );
	foreach $S ( $rdata->Sections() ) {
		my $sn;
		foreach $sn ( $rdata->val( $S, 'ShortName' ) ) {
			push @wadg::rm::Settings::KNOWN_REPORTS, $sn;
		} # end foreach
	} # end foreach
} # end scope

#
# - Get user configuration (without losing data already in %config...)
#
tie %config, 'wadg::rm::Settings', ( 
	-argv    => \@ARGV,
	-version => $HEADER,
	-default => 'reports',
	-preset  => \%config,
);

#
# Throw an error message if that fails
#
unless( %config && defined( tied(%config) ) ) {
	# -- Make sure error messages are printed in this case!
	$statistics{Verbose} .= 'E';
	# Get the filenames that should have been tried:
	my $requested = join( ',', grep( !/^-/, @ARGV ) );
	if( $requested ) {
		wadg::Errors::error( -1, 'E0014', $requested );
	} else {
		# Get the default name part.
		my( $base ) = fileparse( $0, '\..*' );
		wadg::Errors::error( -1, 'E0009', $base );
	} # end if
} # end unless


#
# -- Separate out the program specific parts of the settings
#
%statistics = %{$config{statistics}};
tied(%config)->get_nav_styles();
%navigation = %{$config{navigation}};
delete $config{statistics};
delete $config{navigation};
$config{reports}{Meta_Refresh} = $statistics{Meta_Refresh};
$config{reports}{No_Robots} = $statistics{No_Robots};
$config{reports}{Format} = $statistics{Format};


#
# - Get input report settings and text files in the user's language
#
{	# Scope for variables
	# Default language is 'en'
	$statistics{Language} = 'en' unless defined $statistics{Language};
	
	my @language = ($RealBin, 'lang', $statistics{Language});

	# Do new lang.ini here only if not english, 'cause english is already loaded
	if( $statistics{Language} ne 'en' ) {
		my $fileN = File::Spec->catfile( @language, 'lang.ini' );
		unless( -e $fileN ) {
			wadg::Errors::error( -1, 'E0011', $fileN );
		} # end if
		$lang = new Config::IniFiles( -file => $fileN, -import => $lang );
	} # end if

	# Load the language-specific extensions
	# Can import the object we're writing to 'cause import makes a copy.
	my $fileN = File::Spec->catfile( @language, 'rdata.ini' );
	unless( -e $fileN ) {
		wadg::Errors::error( -1, 'E0011', $fileN );
	} # end if
	$rdata = new Config::IniFiles( -file => $fileN, -import => $rdata );

	$fileN = File::Spec->catfile( @language, 'cdata.ini' );
	unless( -e $fileN ) {
		wadg::Errors::error( -1, 'E0011', $fileN );
	} # end if
	$cdata = new Config::IniFiles( -file => $fileN, -import => $cdata );
} # end scope



#
# Build next level of inheritance by inserting $rdata into %config
#
delete $config{x};
delete $config{q};
{ # scope for variables
	my( $S, $P, %short_names );
	# -- Push the rdata under config, gathering a shortname -> letter mapping
	foreach $S ( $rdata->Sections() ) {
		my $sn;
		foreach $sn ( $rdata->val( $S, 'ShortName' ) ) {
			$short_names{uc($sn)} = $S if $sn;
		} # end foreach
		$config{$S} = {} unless ref $config{$S} eq 'HASH';
		foreach $P ( $rdata->Parameters( $S ) ) {
			$config{$S}{$P} = $rdata->val( $S, $P ) unless defined $config{$S}{$P};
		} # end foreach
	} # end foreach
	# -- Now convert shortname sections to letters overriding the letter values
	foreach $S (keys %config) {
			next unless defined $short_names{uc($S)};
			$config{$short_names{uc($S)}} = {} unless ref $config{$short_names{uc($S)}} eq 'HASH';
			foreach $P (keys %{$config{$S}}) {
				$config{$short_names{uc($S)}}{$P} = $config{$S}{$P};
			} # end foreach
			delete $config{$S};
	} # end foreach
} # end scope

# -- Localize the formatter
$formatter->localize( 'day_abrev', $lang->val( 'Dates', 'shortDays' ) );
$formatter->localize( 'day_names', $lang->val( 'Dates', 'longDays' ) );
$formatter->localize( 'month_abrev', $lang->val( 'Dates', 'shortMonths' ) );
$formatter->localize( 'month_names', $lang->val( 'Dates', 'longMonths' ) );
$formatter->localize( 'number_sep', $lang->val( 'Symbols', 'decimalList' ) );
$formatter->localize( 'decimal_sep', $lang->val( 'Symbols', 'decimalSeparator' ) );
$formatter->localize( 'decimal_digits', $lang->val( 'Symbols', 'decimalDigits' ) );
$formatter->localize( 'percent', $lang->val( 'Symbols', 'percent' ) );


# -- Configure the Report class
# --- Rather than settings globals here, lets create a 'report defaults' hash that sets
#     the rest of the default options ( CDATA => $cdata, LANG => $lang, FORMATTER => $formatter )
#     Then call 'new wadg::rm::Report( token => $reportType, CONFIG => $config{$reportType}, %report_defaults )'
my %report_defaults = ( _CDATA => $cdata, _LANG => $lang, _FORMATTER => $formatter, _CONFIG => \%config );
$wadg::rm::Report::FORMATTER     = $formatter;
$wadg::rm::Report::LANG     = $lang;
$wadg::rm::Report::CONFIG    = \%config;

#---------------------------------------#
# If there's an error log file, open it #
#---------------------------------------#
if( $statistics{Log_File} ) {
	my @now = localtime;
	my $now = (1900 + $now[5]) . '/' . (1 + $now[4]) . '/' . $now[3] . ' ' . $now[2] . ':' . $now[1];
	my $infile;
	($infile, undef, undef) = fileparse( $statistics{File_In}, '\..*' );
	$statistics{Log_File} =~ s/%infile%/$infile/gi;
	$statistics{Log_File} =~ s/\${infile}/$infile/gi;
	$statistics{Log_File} =~ s/%infile%/$infile/gi;
	$statistics{Log_File} =~ s/%([^%]+)%/$formatter->formatDate( $1, $now )/ge;

	if( !open( $logFile, ">>$statistics{Log_File}" ) ) {
		wadg::Errors::error( -1, 'E0012', $statistics{Log_File} );
	} # end if
	# - Tell user of logfile on STDOUT
	print( $formatter->formatMessage( $lang->val( 'Errors', 'N0011' ), $statistics{Log_File} ) . "\n" );
} # end if
# - Send output to the logfile (or STDERR)
#   and auto-flush (so user can 'tail -f')
select( $logFile );
$| = 1;

# - Output the starting notice and date/time.
my $now = localtime;
message( 'N0004', $now );

#-----------------------------------#
# Configure and format our settings #
#-----------------------------------#
# -- Convert any date formatting codes in the input file name using today's date
my @now = localtime;
$now = (1900 + $now[5]) . '/' . (1 + $now[4]) . '/' . $now[3] . ' ' . $now[2] . ':' . $now[1];
$statistics{File_In}	=~ s/%([^%]+)%/$formatter->formatDate( $1, $now )/ge;
my $infile;
($infile, undef, undef) = fileparse( $statistics{File_In}, '\..*' );


# -- Build a quick_summary report object
# We will push max values onto this report's _summaries list
# but it would be better if we could push them on the CROParser
# so we can remove the whole redundant report building at the end!
my $quick_summary = undef;
if( defined $config{q}{Rows} && ($config{reports}{File_Out} ne '-')) {
	# Update QuickSummary ALL list if necessary
	if( $config{q}{Rows} =~ /ALL/i ) {
		my( $rep, @repList );
		foreach $rep ( keys %config ) {
			if( defined $rdata->val( $rep, 'MostActive' ) ) {
				push @repList, $rep;
			} # end if
		} # end if
		$config{q}{Rows} = join( ',', @repList );
	} # end if

	my $reportStyle = $config{q}{ReportType};
	$reportStyle =~ s/^\s*(.+)\s*$/$1/;
	if( "wadg::rm::Report::$reportStyle"->isa( 'wadg::rm::Report::QuickSummary' ) ) {
		$quick_summary = "wadg::rm::Report::$reportStyle"->new( token => 'q', %report_defaults );
	} else {
		# -- Unknown style, so notify the user and dump the report
		wadg::Errors::warning( 'W0003', $reportStyle, 'q' );
	} # end if

	$wadg::rm::Report::QuickSummary::CONFIG = \%config;
} # end if


#-----------------------------------#
# Start processing the data file    #
#-----------------------------------#
# - Output notice of settings file and input file being read
message( 'N0002', tied(%config)->getFilename() );
message( 'N0005', $statistics{File_In} );

# Add Analog paths if CGI mode has been configured and load data
if( exists $config{CGI}{Analog_Config} ) {
	$croParser->{Analog} = $config{CGI}{Analog};
	$croParser->{Analog_Config} = $config{CGI}{Analog_Config};
	wadg::Errors::error( -1, 'E0020' ) if $croParser->getFile();
}
# Otherwise Get data from Analog's computer readable output file
elsif ( $croParser->getFile( $statistics{File_In} ) ) {
	wadg::Errors::error( -1, 'E0005', $statistics{File_In}, "\n");
} # end if

# Set a default title, if none is given
if( !defined $config{website}{Title} && defined $croParser->{globals}{HN} ) {
	$config{website}{Title} = $formatter->formatMessage( $lang->val( 'Text', 'O0014' ), $croParser->{globals}{HN} );
} # end if

# Set a default base URL, if none is given
if( !defined $config{website}{Base_URL} && defined $croParser->{globals}{HU} ) {
	$config{website}{Base_URL} = $croParser->{globals}{HU};
} # end if



# 
# Convert any outfiles that contain formatting codes or stdout specifier
# use date of last request OR current date if date of last request is undefined
#
if( defined $croParser->{globals}{DataEnd} ) {
	$now = $formatter->getDateString( @{$croParser->{globals}{DataEnd}} );
} else {
	my @now = localtime;
	$now = (1900 + $now[5]) . '/' . (1 + $now[4]) . '/' . $now[3] . ' ' . $now[2] . ':' . $now[1];
} # end if

# - Format the date globals in the CROParser to our specs
if( defined $croParser->{globals}{GenerationTime} ) {
	$croParser->{globals}{GenerationTime} = $formatter->formatDate( $lang->val( 'Text', 'O0008' ), $formatter->getDateString( @{$croParser->{globals}{GenerationTime}} ) );
} # end if
if( defined $croParser->{globals}{DataStart} ) {
	$croParser->{globals}{DataStart} = $formatter->formatDate( $lang->val( 'Text', 'O0008' ), $formatter->getDateString( @{$croParser->{globals}{DataStart}} ) );
} # end if
if( defined $croParser->{globals}{DataEnd} ) {
	$croParser->{globals}{DataEnd} = $formatter->formatDate( $lang->val( 'Text', 'O0008' ), $formatter->getDateString( @{$croParser->{globals}{DataEnd}} ) );
} # end if

foreach ( $config{reports}{File_Out}, 
          $navigation{File_Out}, 
          $statistics{Frame_File_Out}, 
          $statistics{Log_File},
          $statistics{Include},
          $config{website}{Title},
          $croParser->{header},
          $croParser->{footer},
        ) {
	next if !defined;
	s/%infile%/$infile/gi;			# For backward compatibility
	s/\$\{infile\}/$infile/gi;
	s/\$\{([^\:\}]+)\:([^\}]+)\}/$formatter->format_value( $2, $croParser->{globals}{$1}) || "\${$1:$2}"/ge;
	s/\$\{([^\:\}]+)\}/$croParser->{globals}{$1} || "\${$1}"/ge;
	s/%([^%]+)%/$formatter->formatDate( $1, $now )/ge;
} # end foreach
$wadg::rm::Report::GLOBALS = $croParser->{globals};

#---------------------------------#
# Begin creating the reports      #
#---------------------------------#
# - Create initial report files
my $report_writer = &openOutputFiles( $config{reports}{File_Out} );

#
# Start reading input data and process according to report type
#
my( $report, $columns) = 
  ( '',      '',     );

my @lineData;
my $currentReport = new wadg::rm::Report( code => undef );
$currentReport->{token} = '';

#
# Now process the rest of the reports.
#
while( !$croParser->eof ) {

	( $report, $columns, @lineData ) = $croParser->nextLine();
	
	#
	# When report changes, start new report.
	#
	if( $report ne $currentReport->{token} ) {
		# Finish old report
		#   - Push summaries onto quick_summary
		if( defined $quick_summary && defined $config{$currentReport->{token}}{ShortName}) {
			my( $dType ) = split( /[\012\015]+/, $config{$currentReport->{token}}{ShortName});
			my $summ = $currentReport->{_summaries}{$dType}{max};
			if( defined $summ ) {
				$quick_summary->{_summaries}{$dType} = {} unless defined $quick_summary->{_summaries}{$dType};
				$quick_summary->{_summaries}{$dType}{max} = {} unless defined $quick_summary->{_summaries}{$dType}{max};
				foreach ( keys %{$summ} ) {
					$quick_summary->{_summaries}{$dType}{max}{$_} = $summ->{$_};
				} # end foreach
			} # end if
		} # end if
		#   - Outputs summaries and close table, close file if multi-file mode
		if( ($statistics{One_File} != 1) && (defined $currentReport->{writer}) ) {
			undef $currentReport->{REPORTSPAN};		# No duplicate dates
			$currentReport->end_report();
			wadg::rm::Report::closeReportFile( $currentReport->{writer}, $croParser->{footer}, $currentReport->{token} );
		} else {
			$currentReport->end_report();
		} # end if
		
		# -- Skip blank lines
		next unless defined $report;

		# -- Start the new report, extensibly
		my $reportStyle = $config{$report}{ReportType};
		$reportStyle =~ s/^\s*(.+)\s*$/$1/;
		if( $reportStyle eq 'Simple' ) {
			$currentReport = new wadg::rm::Report( token => $report, %report_defaults );
		} elsif( !defined $reportStyle ) {
			# -- Unknown report, so notify the user and dump the report
			wadg::Errors::warning( 'W0001', $report );
			$croParser->nextReport();
			next;
		} elsif( "wadg::rm::Report::$reportStyle"->isa( 'wadg::rm::Report' ) ) {
			$currentReport = "wadg::rm::Report::$reportStyle"->new( token => $report, %report_defaults );
		} elsif( $reportStyle->isa( 'wadg::rm::Report' ) ) {
			$currentReport = new $reportStyle( token => $report, %report_defaults );
		} else {
			# -- Unknown style, so notify the user and dump the report
			wadg::Errors::warning( 'W0003', $reportStyle, $report );
			$croParser->nextReport();
			next;
		} # end if
		
		# -- If multiple report files, then start a new file here
		if( $statistics{One_File} != 1 ) {
			my( $sn ) = split /[\012\015]+/, $config{$report}{ShortName};
			my $fileN = File::Spec->catfile( $config{reports}{File_Out}, "$sn" . $config{$report}{File_Extension} );
			message( 'N0001', $fileN );
			$report_writer = wadg::rm::Report::openReportFile( $fileN, $croParser->{header}, $report );
			unless( defined $report_writer ) {
				wadg::Errors::error( -1, 'E0008', $fileN );
			} # end unless
		} # end if
		$currentReport->{writer} = $report_writer;
		$currentReport->{columns} = $columns;
		$currentReport->{_GLOBALS} = $croParser->{globals};

		# - Output new report title & description
		$currentReport->title();
		$currentReport->description();

		# -- Ouput the first table
		if( $currentReport->isa( 'wadg::rm::Report::GeneralSummary' ) ) {
			next if $currentReport->start_table();
		} else {
			$currentReport->start_table();
			# -- Good report, now set a default for Active_Column if it's not already set
			if( !defined $config{reports}{Active_Column} ) {
				$config{reports}{Active_Column} = substr( $columns, 0, 1 );
				if( $config{reports}{Active_Column} eq uc($config{reports}{Active_Column}) ) {
					$config{reports}{Active_Column} .= '_';
				}  # end if
			} # end if
			
		} # end if
		
	} elsif( $currentReport->{columns} ne $columns ) {
		# When COLUMNS change, close old table and start new one.
		# Except in case of a General Summary
		unless( $currentReport->isa( 'wadg::rm::Report::GeneralSummary' ) ) {
			# - Need to close table
			$currentReport->end_table();

			# - Now, start a new one
			$currentReport->{columns} = $columns;
			while( $currentReport->start_table() ) {
				# If this returns non-zero then the report is not defined,
				# so, just dump the report
				$croParser->nextReport();
				next;
			} # end while
		} # end unless
		$currentReport->{columns} = $columns;
	} # end if


	#
	# Process each report line in the current report context.
	#
	$currentReport->process( @lineData );
	
} # end while

#---------------------------------------#
# Finish up all the processing and quit #
#---------------------------------------#
# - Finish the last report
$currentReport->end_report();

# - Close the output file
&closeOutputFile( $report_writer );

# - Quick summary reopens the output file to insert summary information
$report = 'q';
if( defined $config{$report}{Rows} && defined $quick_summary ) {
	
	# Store the globals
	$quick_summary->{_GLOBALS} = $croParser->{globals};
	
	# File name for single file mode is the output file
	my $fileN = $config{reports}{File_Out};
	
	# -- Use Report to open new file or QuickSummary to insert in current one
	if( $statistics{One_File} == 0 ) {
		my( $sn ) = split /[\012\015]+/, $config{$report}{ShortName};
		$fileN = File::Spec->catfile( $config{reports}{File_Out}, "$sn" . $config{$report}{File_Extension} );
		message( 'N0001', $fileN );
		$report_writer = wadg::rm::Report::openReportFile( $fileN, $croParser->{header}, $report );
	} else {
		$report_writer = wadg::rm::Report::QuickSummary::openReportFile( $config{reports}{File_Out}, $croParser->{header}, $report );
	} # end if
	unless( defined $report_writer ) {
		wadg::Errors::error( -1, 'E0008', $fileN );
	} # end unless
	
	$quick_summary->{writer} = $report_writer;
	$quick_summary->{handle} = $report_writer->{file};
	
	# For the columns, use the active column value and percent-of for the headers
	my $ac = substr($config{reports}{Active_Column}, 0, 1);
	$quick_summary->{columns} = 'T' . uc($ac) . lc($ac);

	$quick_summary->title();
	$quick_summary->description();
	$quick_summary->start_table();
	$quick_summary->process();
	$quick_summary->end_report();

	if( $statistics{One_File} == 0 ) {
		wadg::rm::Report::closeReportFile( $quick_summary->{writer}, $croParser->{footer}, $quick_summary->{token} );
	} else {
		wadg::rm::Report::QuickSummary::closeReportFile( $quick_summary->{writer}, $croParser->{footer}, $quick_summary->{token} );
	} # end if
} # end if
# - Output the complete notice and date/time.
$now = localtime;
message( 'N0010', $now );

&finalize( 0 );



###################################################
#                                                 #
#             Functions                           #
#                                                 #
###################################################

# ----------------------------------------------------------
# Sub: openOutputFiles
#
# Args: $filename
#	$filename	The name of the file to store reports in
#
# Description: Opens the output report file, frameset and 
#              navigation file.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created by Corey Kaye / DNS                  CK
# 1999Feb19 Modified to support multi-file reports       JW
# 1999Feb24 Added support for background images and 
#           title font                                   JW
# 1999Nov17 Changed NavFile to support non-frames mode   JW
# 2000Mar21 Modified to use $filename parameter          JW
# ----------------------------------------------------------
sub openOutputFiles {
	# - This is the system-style filename
	my $fileName = shift;
	# - These are the URL style HREFs
	my $fileNav = '';
	my $reportFile;
	
	# - Use fileparse() to get $outDir, 'cause dirname() will make 
	#   'reports/' into '.' and we want 'reports/'
	my $outDir;
	( undef, $outDir, undef ) = fileparse( $fileName );

	# - Make outDir if it's not there
	if( !-e($outDir) ) {
		mkpath( $outDir );
	} # end if

	# In multifile report, first page is General Summary
	if( $statistics{One_File} != 1 ) {
		message( 'N0006', $outDir );
		###*** Note that the value $config{GENERAL}{File_Extension} is coming up 
		###    undefined here (shouldn't it default to {reports}?) so reports is 
		###    used. If someone does [GENERAL]File_Extensions=xxx this WILL FAIL!!!
		$fileName = File::Spec->catfile( $fileName, 'GENERAL' . $config{reports}{File_Extension} );
	} else {
		message( 'N0008', $fileName );
	} # end if
	$fileName = basename( $fileName );

	my $ln = $lang->val( 'Language', 'Symbol' );

	#
	# Make index File, if doing frameset.
	#
	if( $navigation{File_Out} !~ /^(LEFT|RIGHT|TOP|BOTTOM|0)$/i ) {
		# - Output notices of file being created
		message( 'N0009', $statistics{Frame_File_Out} );

		local *indexFile;
		$fileNav = $navigation{File_Out};
		$fileNav = basename( $fileNav );

		unless( open(*indexFile,">$statistics{Frame_File_Out}") ) {
			wadg::Errors::error( -1, 'E0006', $statistics{Frame_File_Out} );
		} # end unless
   
   	# Get the HTMLWriter object for this file
   	my $iw = new wadg::HTMLWriter( -file => *indexFile, -output => $statistics{Format} );
		my $norobots = "";
		if( exists $statistics{No_Robots} && defined $statistics{No_Robots} && $statistics{No_Robots} == 1 ) {
			$norobots = $iw->meta( {name => 'ROBOTS', content => 'NOINDEX,NOFOLLOW' } );
		} # end if
   	
		$iw->write( $iw->doctype( {-flavor => 'Frameset'} ) );	# -flavor is ignored by HTML 3.2
		$iw->write( $iw->start_html( {lang => $ln} ) );
		$iw->write( $iw->head( $iw->meta( {name => 'AUTHOR', content => "This page created by $config{_INTERNAL}{'_TITLE'} $config{_INTERNAL}{'_VERSION'}"} ),
		                       $iw->title( $config{website}{Title} ), 
		                       $norobots) );
		my %frameset = ( cols => "22%,*" );
		
		if( defined $statistics{Frame_Border} ) {
			$frameset{border} = $statistics{Frame_Border} if $statistics{Frame_Border} ne '';
			$frameset{frameborder} = 'no' unless $frameset{Frame_Border};
		} # end if
		$iw->write( $iw->start_frameset( \%frameset ) );
		$iw->write( $iw->frame( {src => $fileNav, 
		                         name => 'NAV', 
		                         scrolling => 'AUTO', 
		                         title => $lang->val( 'Text', 'O0010' )
		                        } ) );
		$iw->write( $iw->frame( {src => $fileName, 
		                         name => 'CONTENT', 
		                         scrolling => 'AUTO', 
		                         title => $lang->val( 'Text', 'O0011' )
		                        } ) );
		$iw->write( $iw->noframes( $formatter->formatMessage( $lang->val( 'Text', 'O0001' ), $fileNav ) ) );
		$iw->write( $iw->end_frameset() );
		$iw->write( $iw->end_html() );

		close *indexFile;
	} # end if

	#
	# Make Report File
	# If doing a single report file then create that here, otherwise
	# if doing multiple report files, they will be created at each report
	#
	if( $statistics{One_File} == 1 ) {
		$reportFile = wadg::rm::Report::openReportFile( $config{reports}{File_Out}, $croParser->{header}, 'reports' );
		unless( defined $reportFile ) {
			wadg::Errors::error( -1, 'E0008', $config{reports}{File_Out} );
		} # end unless
	} # end if

	#
	# Make NavMenu
	# Get the content and, if doing frames then store that into a
	# file, otherwise just keep it for each report table
	#

  	# Get the HTMLWriter object for this file
  	my $nw = new wadg::HTMLWriter( -output => $statistics{Format}, -stylesheet => $navigation{_styles} );
  	%{$navigation{website}} = %{$config{website}};
  	$navigation{reports_File_Out} = $config{reports}{File_Out};
  	$navigation{reports_File_Extension} = $config{reports}{File_Extension};
  	$navigation{One_File} = $statistics{One_File};
  	$navigation{Summary_Rows} = $config{q}{Rows} unless $config{reports}{File_Out} eq '-';
	my $navmenu = wadg::rm::Report::createNavMenu( $croParser, $nw, \%navigation );

	if( $navigation{File_Out} !~ /^(LEFT|RIGHT|TOP|BOTTOM|0)$/i ) {
		# - Output notices of file being created
		message( 'N0007', $navigation{File_Out} );
		# -- Open the output file and write this all out.
		local *navFile;
		unless( open(*navFile,">$navigation{File_Out}") ) {
			wadg::Errors::error( -1, 'E0007', $navigation{File_Out} );
		} # end unless
		$nw->{file} = *navFile;
		
		my $cs = '';
		if( defined $lang->val( 'Language', 'CharacterSet' ) ) {
			$cs = $nw->meta( {'http-equiv' => 'Content-Type', content => 'text/html; charset=' . $lang->val( 'Language', 'CharacterSet' ) } );
		} # end if
		my $norobots = '';
		if( exists $statistics{No_Robots} && defined $statistics{No_Robots} && $statistics{No_Robots} == 1 ) {
			$norobots = $nw->meta( {name => 'ROBOTS', content => 'NOINDEX,NOFOLLOW' } );
		} # end if

		$nw->write( $nw->doctype( {-flavor => 'Transitional'} ) );		# -flavor is ignored by HTML 3.2
		$nw->write( $nw->start_html( { lang => $ln} ) );

		my $stylesheet = '';
		if( exists $navigation{Stylesheet} && defined $navigation{Stylesheet} && $navigation{Stylesheet} =~ /\w+\s*\{\s*\w+\s*:.*}/ ) {
			$stylesheet = $nw->style( {type => 'text/css'}, $navigation{Stylesheet} );
		} elsif( exists $navigation{Stylesheet} && defined $navigation{Stylesheet} && $navigation{Stylesheet} ) {
			$stylesheet = $nw->link( { type => 'text/css', href => $navigation{Stylesheet}, rel => 'STYLESHEET' } );
		} # end if
		$nw->write( $nw->head( $cs,
		                       $nw->meta( {name => 'AUTHOR', content => "This page created by $config{_INTERNAL}{'_TITLE'} $config{_INTERNAL}{'_VERSION'}"} ),
		                       $norobots,
		                       $nw->title( $lang->val( 'Text', 'O0010' ) ),
		                       $stylesheet,
		                     ) );

		$nw->write( $nw->body( $navmenu ) );
		$nw->write( $nw->end_html() );
		close *navFile;
	} else {
		$config{reports}{Navigation_Writer} = $nw;
		$config{reports}{Navigation_Content} = $navmenu;
		$config{reports}{Navigation_Position} = uc($navigation{File_Out});
		$config{reports}{Navigation_Background} = $navigation{Background};
		$config{reports}{Navigation_BG_Color} = $navigation{BG_Color};
	} # end if
	
	#
	# Copy logos to destination directory, if not using a logo file
	# and not storing logos in a central place.
	#
	if( !$config{website}{Company_Logo} && !$config{reports}{Image_Dir} ) {
		copy( File::Spec->catfile( $RealBin, 'rmlogo.png' ), File::Spec->catfile( $outDir, 'rmlogo.png' ) );
		copy( File::Spec->catfile( $RealBin, 'analogo.png' ), File::Spec->catfile( $outDir, 'analogo.png' ) );
	} # end if

	return $reportFile
	
} # end openOutputFiles

# ----------------------------------------------------------
# Sub: closeOutputFile
#
# Args: $reportFile
# 	$reportFile	A handle for the file to be closed
#
# Description: Closes the report file at the end of 
#              single file mode.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created by Jeremy Wadsack / WADG              JW
# 2000Oct18 Fixed file corruption bug                     JW
# 2001Feb06 Fixed bug in closing of output file           JW
# ----------------------------------------------------------
sub closeOutputFile {
	my $reportFile = shift;
	return wadg::rm::Report::closeReportFile( $reportFile, $croParser->{footer}, 'reports' );
} # end closeOutputFile

# ----------------------------------------------------------
# Sub: message
#
# Args: $code, @args
#	$code	A code to look up in the Errors section of the language file
#	@args	A set of arguments to send into the $code's format
#
# Description: Output's a message to the screen or logfile
# based on the verbosity settings
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Apr30 Created messaging function                    JW
# 1999Sep02 Added support for logfiles                    JW
# 1999Oct14 Added Verbosity control                       JW
# 2000Apr25 Made suitable for an exception handler        JW
# 2000Jul06 Moved header and prefix back here             JW
# 2001Jan04 Forced scalar context for $lang-val()         JW
# 04Feb2003 Added 'WE' for pre-processing stage           JW
# ----------------------------------------------------------
#
# DANGER WILL ROGERS: This is probably a lot more than an
# error handler should do....
#
sub message {
	my($code, @args) = @_;

	#
	# Before any settings are processed, we have to assume warnings and errors
	# are good to show
	#
	$statistics{Verbose} = 'WE' unless exists $statistics{Verbose};
	
	#
	# Now write the message to the selected handle (log file or stderr)
	#
	if( index( $statistics{Verbose}, substr($code, 0, 1) ) != -1 ) {
		my $msg = $lang->val( 'Errors', $code );
		$msg = $formatter->formatMessage( $msg, @args );
		$msg = "$PREFIX$msg\n";

		if( defined $HEADER && !$HEADER_USED ) {
			$msg = $HEADER . $msg;
			$HEADER_USED = 1;
		} # end if

		print $msg;
	} # end if
	
	
} # end message

# ----------------------------------------------------------
# Sub: finalize
#
# Args: errorlevel, [@message]
#	errorlevel	An error code to return the the shell (if applicable)
#	@message		Optional list to send to &message before dying
#
# Description: A fatal exception exception handler that will 
# clean up the system and exit. Will return an error state 
# to the shell, where applicable. Will print a message before
# exiting if provided. Will exit soft on Macs unless logging 
# or statistics_Always_Quit is set. Otherwise always exists hard.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#      1999 Created function and debugged Mac end         JW
# 2000APR25 Moved messaging inside funtion and made into
#           a fatal exception handler                     JW
# 27Feb2003 Added browser message for CGI mode            JW
# ----------------------------------------------------------
#
# WARNING: See note under &message above
#
sub finalize {
	my( $arg, $code, @msg ) = @_;

	# - If there's a message parm, do that first
	&message( $code, @msg ) if $code;

	# - If there's a log file, close it
	if( $statistics{Log_File} ) {
		close( $logFile );
	} # end if

	# - If running on a Mac then process hard exit 
	if( $^O eq 'MacOS' ) {
		if( defined $statistics{Log_File} || defined $statistics{Always_Quit} ) {
			MacPerl::Quit( 1 );
		} # end if
	} # end if

	#
	# If we're in CGI mode then send something to the browser
	# Except ignore last finalize(0) because that's just an 'exit'
	#
	if( exists $config{_INTERNAL}{_CGI} && defined $code ) {
		my $T = $lang->val( 'Errors', 'E0018' );
		my $m = $lang->val( 'Errors', 'E0019' );
		print STDOUT qq[
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" >
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$T</title></head>
<body>
<h1>$T</h1>
<p>$m</p>
<p>[$arg] [$code] @msg</p>
</body>
</html>
];

	} # end if


	exit( $arg );
} # end finalize
