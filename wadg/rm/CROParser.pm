#
# TODO
#		* Make it work more like a parser....
#       - Store $report and $columns in state variables.
#       - Return data (parse content) from nextLine()
#       - Possibly remove splitLine ... It seems pointless
#
############################################################
#
# Module: wadg::rm::CROParser
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
############################################################
package wadg::rm::CROParser;
use strict;
use wadg::Errors;

BEGIN {
	use vars       qw($VERSION @ISA);

	$VERSION = do { my @r = (q$Revision: 2.20 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

	@ISA         = qw();
} # end BEGIN
# non-exported package globals go here
use vars      qw();


############################
## The object constructor ##
############################
sub new {
	my $self = {};
	my $proto = shift;
	my %parms = @_;
	my $class = ref($proto) || $proto;

	# Parse named parameters
	my($k, $v);
	local $_;
	while( ($k, $v) = each %parms ) {
		$self->{$k} = $v;
	} # end while 

	# Initialize variables
	$self->{separator} = '';    # Stores the separator characters(s) used in the file
	$self->{header} = undef;    # Stores the header in from the data file
	$self->{footer} = undef;    # Stores the footer from the data file
	$self->{globals} = {};      # Stores several global variables parsed from the General Summary
	$self->{lines} = [];        # Stores the complete set of report lines in memory
	$self->{currentLine} = 0;   # Stores the current line number to be read
	$self->{eof} = 0;           # Whether the parser is at the end-of-file (see ->eof method)
	
	bless ($self, $class);
	return $self;
} # end new




##########################
##                      ##
##    Public Methods    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: getFile
#
# Args: $filename
#	$filename	The name of the CRO file to read in
#
# Returns: 
# 0 on success, other error code on failure. Errors
# code return values are as follows
#	-1	Error opening the filename requested
#
# Description: Reads in an Analog CRO file to be parsed
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created as readInputFile by Corey Kaye / DNS  CK
# 1999Feb19 Support for any separator character           JW
# 2000Mar21 Changed to getFile with filename parameter    JW
#           Also adjusted to use object properties        JW
# 03Aug2001 Modified to support alien EOLs                JW
# 14Dec2001 Fixed bug in alien EOL support                JW
# 09Mar2003 Added reading from an Analog process in CGI   JW
# ----------------------------------------------------------
sub getFile {
	my $self = shift;
	$self->{filename} = shift;
	my( @lData );
	
	
	#
	# If this is CGI then get input from an Analog process
	#
	if( exists $self->{Analog} && exists $self->{Analog_Config} ) {
		
		#
		# Now get the data from analog
		#
		
		## NOTE: We can't use IPC::Open2 here because it will lead to deadlock on the pipes
		# local( *AIN, *AOUT );
		# my $cid = open2( *AOUT, *AIN, $self->{Analog}, '+g-' ) || return -1;
		# print AIN join( "\n", @{$self->{Analog_Config}} );
		# return -1 unless close(AIN);
		# my @lines = <AOUT>;
		# return -1 unless close(AOUT);
		# waitpid( $cid, 0 );	# Wait for the process to end stop reading/writing
		
		## So use a temporary file.
		# On Windows, only one process can have a file open for writing at a time
		# so re-open as a read-only handle and close the writing handle
		use File::Temp qw( tempfile );
		my( $fh, $fname ) = tempfile( UNLINK => 1 );
		open( AIN, "<$fname" ) || return -1;
		close $fh;
		
		# Because Windows doesn't like filenames with spaces even though it supports them
		# Taken from anlgform.pl, Stephen R. E. Turner
		if( $^O =~ /win32/i || $^O =~ /^win/i ) {
			 $self->{Analog} = Win32::GetShortPathName($self->{Analog}) if Win32::GetShortPathName($self->{Analog});
			 $fname = Win32::GetShortPathName($fname) if Win32::GetShortPathName($fname);
		} # end if
		

		open( ANALOG, '| ' . $self->{Analog} . " +g- > $fname" );		# Errors on close with pipe
		print ANALOG join( "\n", @{$self->{Analog_Config}} );
		return -1 unless close(ANALOG);
		
		# Seek to top of $fh, just in case
		seek( AIN, 0, 0 );
		
		# Now read file and close handle
		my @lines = <AIN>;
		close AIN;
		
		# Clean the lines, removing any headers
		chomp @lines;
		my $i;
		for( $i = 0; $i < @lines; $i++ ) {
			last if $lines[$i] eq '';		# End of headers
			$lines[$i] = '' if $lines[$i] =~ /^\S+:\s+/;
		} # end for
		$self->{lines} = \@lines;
	}
	#
	# Otherwise get input from the filename given
	#
	else {
		# Open the input file and read it
		return -1 unless open(fileHandle,"<$self->{filename}");
		
		# Get lines from files, supporting alien EOLs
		my @lines = split /\015\012|\012|\015/, join( '', <fileHandle> );
		$self->{lines} = \@lines;
		close fileHandle;
		chomp( @{$self->{lines}} );
	} # end if



	#
	# Find out what the separator character is, get some important 
	# report-wide stats and remove headers and footers
	#
	my $separator = '';
	my( $header, $footer );
	my $linecount = 0;
	foreach( @{$self->{lines}} ) {
		if( /^x/ ) {
			if( /^x(.+?)PS\1/ ) {
				$separator = quotemeta($1) if $separator eq '';
				( undef, undef, @lData ) = split( $separator );
				$self->{globals}{'GenerationTime'} = [];
				@{$self->{globals}{'GenerationTime'}} = @lData;
			} elsif( /^x(.+?)FR\1/ ) {
				$separator = quotemeta($1) if $separator eq '';
				( undef, undef, @lData ) = split( $separator );
				$self->{globals}{'DataStart'} = [];
				@{$self->{globals}{'DataStart'}} = @lData;
			} elsif( /^x(.+?)LR\1/ ) {
				$separator = quotemeta($1) if $separator eq '';
				( undef, undef, @lData ) = split( $separator );
				$self->{globals}{'DataEnd'} = [];
				@{$self->{globals}{'DataEnd'}} = @lData;
			} elsif( /^x(.+?)VE\1/ ) {
				$separator = quotemeta($1) if $separator eq '';
				( undef, undef, @lData ) = split( $separator );
				$self->{globals}{'AnalogVersion'} = join('', @lData);
			} elsif( /^x(.+?)SR\1/ ) {
				( undef, undef, @lData ) = split( $separator );
				$self->{globals}{'TotalRequests'} = $lData[0];
			} elsif( /^x(.+?)PR\1/ ) {
				( undef, undef, @lData ) = split( $separator );
				$self->{globals}{'TotalPages'} = $lData[0];
			} elsif( /^x(.+?)BT\1/ ) {
				( undef, undef, @lData ) = split( $separator );
				$self->{globals}{'TotalBytes'} = $lData[0];
			} elsif( /^x(.+?)HN\1/ ) {
				$separator = quotemeta($1) if $separator eq '';
				( undef, undef, @lData ) = split( $separator );
				$self->{globals}{HN} = join( ' ', @lData );
			} # end if
			if( $separator ne '' ) {
				my $rn;
				( undef, $rn, @lData ) = split( $separator );
				$self->{globals}{$rn} = join( ' ', @lData );
			} # end if
		} else {
			if( $separator eq '' ) {
				$header = $linecount;
			} else {
				# Use the character class [a-zA-z0-9], rather than \w, because
				# \w will be localized (in Japanese for instance) to other 
				# invalid report codes!
				# *** NOTE this limits report codes to single characters!!
				if( !/^[a-zA-Z0-9]$separator[a-zA-Z0-9\*]+/ && !/^$/) {
					$footer = $linecount;
					last;
				} # end if
			} # end if
		} # end if
		$linecount++;
	} # end foreach

	# - Remove headers before report data and footers after
	if( defined $header ) {
		# If it's all a header, then fail with message
		if( $header + 1 == $linecount ) {
			wadg::Errors::error( -1, 'E0016', $self->{filename} );
		} # end if
		$self->{header} = join( "\n", splice( @{$self->{lines}}, 0, $header + 1 ) );
		# Adjust footer ofset:
		$footer -= $header + 1;
	} # end if
	if( defined($footer) && ($footer > 0) ) {
		$self->{footer} = join( "\n", splice( @{$self->{lines}}, $footer ) );
	} # end if
	
	# Store the separator character
	$self->{separator} = $separator;

	return 0;
	
} # end getFile



# ----------------------------------------------------------
# Sub: nextLine
#
# Args: (None)
#
# Description: Parses and returns the next line in the file
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created as readNextLine by Corey Kay / DNS    CK
# 1999Feb24 Modified to use underscore in CPAS columns    JW
# 2000Mar21 Changed to nextLine and used object props     JW
# 14Dec2001 Patched up warnings                           JW
# ----------------------------------------------------------
sub nextLine {
	my $self = shift;
	$self->{currentLine}++;
	my( $report, $columns, @lineData ) = $self->splitLine();

	# - Read new line, skipping blank ones
	while( ($self->{currentLine} <= $#{$self->{lines}}) && 
	       ($self->{lines}[$self->{currentLine}] eq '') ) {
		$self->{currentLine}++;
		( $report, $columns, @lineData ) = $self->splitLine();
	} # end while 

	# - Adjust capitals by appending underscores (JW)
	if( defined($report) && ($report eq uc($report)) && 
	    ($self->{lines}[$self->{currentLine}] ne '') ) {
		$report .= '_';
	} # end if
	
	# Set eof state
	$self->{eof} = ($self->{currentLine} == $#{$self->{lines}});
	
	return ( $report, $columns, @lineData );
} # end nextLine



# ----------------------------------------------------------
# Sub: nextReport
#
# Args: (None)
#
# Returns: A list of lists, each row containing the results 
# of a nextLine call.
#
# Description: Parses and returns a list of the balance of 
# the lines in the current report. If called sequentially or
# at the end of a report, will the next report. If called in after 
# a call or calls to nextLine, will return the rest of the 
# lines that have the same report type.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr04 Created method                                JW
# 14Dec2001 Patched up warnings                           JW
# ----------------------------------------------------------
sub nextReport {
	my $self = shift;
	my @rows;
	my ( $report, @data );
	
	# Rememeber what the current / next report is. 
	( $report, @data ) = $self->nextLine();
	push @rows, [ $report, @data  ];
	my $old_report = $report;

	# Go through the lines, gathering them up
	while( !$self->eof && defined($report) && ($report eq $old_report) ) {
		( $report, @data ) = $self->nextLine();
		push @rows, [ $report, @data  ];
	} # end while
	
	# == unget_next_line() 
	$self->{currentLine}--;

	# Send back the list of lists
	return @rows;

} # end nextReport


# ----------------------------------------------------------
# Sub: getLineCount
#
# Args: (None)
#
# Description: Helper method to return the number of lines
#              in the current CRO file
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Mar21 Created method                                JW
# ----------------------------------------------------------
sub getLineCount {
	my $self = shift;
	return $#{$self->{lines}};
} # end getLineCount


# ----------------------------------------------------------
# Sub: getCurrentLineNumber
#
# Args: (None)
#
# Description: Helper method to return the number of the 
#              line currently in process
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Mar21 Created method                                JW
# ----------------------------------------------------------
sub getCurrentLineNumber {
	my $self = shift;
	return $self->{currentLine};
} # end getCurrentLineNumber


# ----------------------------------------------------------
# Sub: resetParser
#
# Args: (None)
#
# Description: Helper method to reset the parser line counter
#              to start processing at the top again
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Mar21 Created method                                JW
# ----------------------------------------------------------
sub resetParser {
	my $self = shift;
	$self->{eof} = 0;
	return $self->{currentLine} = 0;
} # end resetParser


# ----------------------------------------------------------
# Sub: eof
#
# Args: (None)
#
# Description: Returns true if parser is at the end of the 
# file, otherwise returns false.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000May04 Created method                                JW
# ----------------------------------------------------------
sub eof {
	my $self = shift;
	return $self->{eof};
} # end eof

# ----------------------------------------------------------
# Sub: splitColumns
#
# Args: $cols, $hashRef, @data
#	$cols   	The list of column labels to assign to
#	$hashRef	Reference to hash to store associations in
#	@data   	The list of data to assign to
#
# Description: Associates a list of data with the columns 
#              and stores the association in the hash ref
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created by Jeremy Wadsack / WADG              JW
# 2000APR20 Converted to CLASS METHOD, adjusted class     JW
# 2000May07 Rewrote with map and removed uc...'_' stuff   JW
# ----------------------------------------------------------
sub splitColumns {
	my( $cols, $hashRef, @myData ) = @_;

	map {$hashRef->{$_} = shift @myData} split(/ */, $cols);
} # end splitColumns



##########################
##                      ##
##   Private Methods    ##
##                      ##
##########################
# ----------------------------------------------------------
# Sub: splitLine
#
# Args: $line
#	$line	A row of CRO data
#
# Description: Splits the row of CRO data into columns
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created by Corey Kaye / DNS                   CK
# 1999Mar08 Modified to pull our report and column spec   JW
# ----------------------------------------------------------
sub splitLine {
	my $self = shift;
	return split( /$self->{separator}/, $self->{lines}[$self->{currentLine}] );
} # end splitline


# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
