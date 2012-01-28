############################################################
#
# Module: wadg::rm::Formatter
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
# 2000.Oct.20 Made split_date a public method             JW
# 14.Jun.2001 Now needs Time::Local for 'www' date fmt    JW
############################################################
package wadg::Formatter;
use strict;
use Time::Local;

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
# Args: ( $item => $data, ... )
#	$item	The name of a localization 
#	$data	The data value or reference to data list to assing for that localization
#
# Description: Creates a new formatter object adding localizations or settings
#
# TODO:
#      * Add defaults
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 
# ----------------------------------------------------------
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

	bless ($self, $class);
	
	# Set the defaults
	$self->{day_abrev} = [qw( Mon Tue Wed Thu Fri Sat Sun )]
		unless exists $self->{day_abrev};
	$self->{day_names} = [qw( Monday Tuesday Wednesday Thursday Friday Saturday Sunday )]
		unless exists $self->{day_names};
	$self->{month_abrev} = [qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec )]
		unless exists $self->{month_abrev};
	$self->{month_names} = [qw( January February March April May June July August September October November December )]
		unless exists $self->{month_names};
	$self->{number_sep} = ',' unless exists $self->{number_sep};
	$self->{decimal_sep} = '.' unless exists $self->{decimal_sep};
	$self->{decimal_digits} = 2 unless exists $self->{decimal_digits};
	$self->{percent} = '%' unless exists $self->{percent};
	$self->{currency} = '$' unless exists $self->{currency};
	$self->{period_string} = '%{y:choice:0#|1# one year, |1#%0 years, }' .
	                         '%{w:choice:0#|1# one week, |1#%0 weeks, }' . 
	                         '%{d:choice:0#|1# one day, |1#%0 days, }' . 
	                         '%{h:choice:0#|1# one hour, |1#%0 hours, }' . 
	                         '%{m:choice:0#|1# one minute, |1#%0 minutes, }' . 
	                         '%{s:choice:0#and %0 seconds.|1#and one second.|1#and %0 seconds.}'
		unless exists $self->{period_string};
	$self->{bytes} = '%0 %1B' unless exists $self->{bytes};
	$self->{bps} = '%0 %1bps' unless exists $self->{bps};
	$self->{byte_pref} = [qw( K M G T P E Y Z )] unless exists $self->{byte_pref};
	
	return $self;
} # end new

##########################
##                      ##
##    Public Methods    ##
##                      ##
##########################

# ----------------------------------------------------------
# Sub: localize
#
# Args: $item @data
#	$item	The name of the localization 
#	@data	The data to use for that localization
#
# Description: Loads the formatter with the localizations to be 
#              used in subsequent formatting operations
#
# Valid 'localizations' include the following names (defaults in quotes):
#     day_abrev       The abreviation for days of the week (Mon, Tues, ...)
#     day_names       The full name of days of the week (Monday, Tuesday, ...)
#     month_abrev     The abreviation for months (Jan, Feb, ...)
#     month_names     The full names of months (January, February, ...)
#     number_sep      The symbols used to separate thousands lists (,)
#     decimal_sep     The symbols to use to separate decimals parts (.)
#     decimal_digits  The number of decimal places to truncate to (2)
#     percent         The symbol to use for percent (%)
#     period_string   A localized string for specifying a full period of time
#     currency        The symbol to use for currency ($)
#     bytes           The phrase for bytes (%0 %1B)
#     bps             The phrase for transfer rate (%0 %1bps)
#     byte_pref       Prefixes for bytes and bps. Start from 'kilo' (k, M, G, T, P, E, Y, Z) 
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Mar20 Created function                              JW
# 2000Apr11 Doc'd, above, and added header                JW
# 2000Jul06 Removed header and prefix.                    JW
# 20Feb2003 Added undef case for $data[0]                 JW
# ----------------------------------------------------------
sub localize {
	my $self = shift;
	my( $item, @data ) = @_;

	# Load localizations
	if( @data > 1 ) {
		$self->{$item} = \@data;
	} elsif( defined $data[0] ) {
		$self->{$item} = $data[0];
	} else {
		$self->{$item} = '';
	} # end if
	
	return;
} # end localize


# ----------------------------------------------------------
# Sub: clone_statement
#
# Args: (None)
#
# Returns: A string that can be eval'd to create a clone
#
# Description: Produces a string that can be evaluated to 
# create a clone of the Formatter object. This can be useful,
# for example, where you need a formatter in an anonymous
# subroutine. Only produces the RVALUE so you need to prepend
# something like '$formatter =' before evaluating.
# 
# Example:
# 		my $sub = eval 'my $fmtr = ' . $formatter->clone_statement . ';';
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 30Aug2001 Added method to support anonymous subs        JW
# ----------------------------------------------------------
sub clone_statement {
	my $self = shift;

	my $statement = ref($self) . '->new(';
	for( keys %$self ) {
		# Single-quote $_ just in case it's got spaces or - or something
		$statement .= "'$_'=>";
		# If it's an array ref, then do each item into an array
		# Notice that we ignore all hash refs and objects!
		if( ref($self->{$_}) eq 'ARRAY' ) {
			$statement .= '[' . join( ',', map "'$_'", @{$self->{$_}} ) . ']';
		} elsif( !ref $self->{$_}) {
			$statement .= "'" . $self->{$_} . "'";		# Perl 5.004 won't interpolate de-references
		} # end if
		$statement .= ',';
	} # end for
	$statement .= ')';
	
	return $statement;
} # end clone_statement


# ----------------------------------------------------------
# Sub: format_value
#
# Args: $format @data
#	$format  A format specifier string using "type:format" where 
#	         type is (number,date,bytes,period,...)
#	@data    The data to format with the format routine
#
# Description: A generic format function that calls the 
# appropriate format method based on the type specifier. The 
# type can be one of date, time, datetime, number, bytes, bps, 
# or period. Period is a period of time (e.g. "5 minutes, 
# 32 seconds"). All formatting is localized, of course.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2001Jan26 Create method to allow generic format specs   JW
# ----------------------------------------------------------
sub format_value {
	my $self = shift();
	my( $format, @data ) = @_;
	my( $val, $type );

	if( $format =~ /\:/ ) {
		( $type, $format ) = $format =~ /^([^\:]+)\:(.*)$/;
	} else {
		$type = $format;
		$format = '';
	} # end if

	if( $type =~ /^(date|time|datetime)$/ ) {
		$val = $self->formatDate( $format, @data );
	} elsif( $type eq 'number' ) {
		$val = $self->formatNumber( $format, @data );
	} elsif( $type eq 'period' ) {
		$val = $self->format_period( $format, @data );
	} elsif( $type eq 'bytes' ) {
		$val = $self->format_bytes( $format, @data );
	} elsif( $type eq 'bps' ) {
		$val = $self->format_bps( $format, @data );
	} elsif( $type eq 'choice' ) {
		$val = $self->format_choice( $format, @data );
	} else {
		$val = join '', @data;
	} # end if
	
	return $val;
} # end format_value




# ----------------------------------------------------------
# Sub: formatDate
#
# Args: $format $date
#	$format	A format specifier string using [ymdwhns] and 'am'/'pm'
#	$date  	A date dataset in the format /yyyy.+mm.+dd.+hh.+mm/
#
# Description: Formats a date based on the passed formmatting 
#              string. Format letters may be either case. Case 
#              is preserved for am/pm. The number of contiguous
#              format letters determines the output (m vs. mmmm).
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Mar08 Create routine based on previous JavaScript   JW
# 1999Jul08 Changed minute specifier to 'n' for i18n      JW
# 2000May04 Fixed bug in 'w' format to only use numbers   JW
# 2001Feb06 Added support for 'q' Quarter format          JW
# 05Jun2001 Does not try to format non-date data          JW
# 14Jun2001 Added ability for week days from a date       JW
# 18Jun2001 Added y2k patch for 2-digit years             JW
# 19Jun2001 Fixed bug in week day formatting              JW
# ----------------------------------------------------------
sub formatDate {
	my $self = shift();
	my( $format, $date ) = @_;
	my( $posF, $m, $charF, $output, $tempStr );
	my( %date );
	
	#
	# Start by separating the date into it's components
	# But, if it doesn't look like a date then just return it as is
	return unless $self->split_date( $date, \%date );

	#
	# We want, in general to use case-insensitive, but we'll
	# keep the original for checking am/pm vs. AM/PM, etc.
	#
	my $caseFormat = $format;
	$format = lc( $format );

	# - Special case: no format spec
	if( length( $format ) == 0 ) {	
		$output = $date;
		$posF = 1;
	} # end if

	# - Special case: single date field
	if( keys %date < 2 ) {	
		$date{month} = $date;
		$date{day} = $date;
		$date{hour} = $date;
		$date{minute} = $date;
		$date{second} = $date;
	} # end if

	#
	# Ok, now process each segment of the format spec
	#
	$posF = 0;
	$output = '';
	$tempStr = '';
	while( $posF < length($format) ) {
		#
		# Count number of repetitions of specifier
		#
		$m = 1;
		$charF = substr( $format, $posF, 1 );
		while( $charF eq substr( $format, ++$posF, 1 ) ) {
			$m++;
		} # end while

		#
		# Create the output based on specifiers
		#
		if( $charF eq 'y' ) {
			# - Add the year to the output
			if( $m < 3 ) {
				$tempStr = $date{'year'};
				if( length($tempStr) > 2 ) {
					$tempStr = substr( $tempStr, length($tempStr) - 2, 2 );
				} # end if
				if( $m > length($tempStr) ) {
					$tempStr = '0' . $tempStr;
				} # end if
			} elsif( $m < 5 ) {
				$tempStr = $date{'year'} || '';
				my $_l = $m - length($tempStr);
				while( $_l-- ) {
					$tempStr = '0' . $tempStr;
				} # end if
			} else {
				# -- Future implementation of "Nineteen Hundred Thirty Six"
				$tempStr = "";
			} # end if 
			$output .= $tempStr;

		} elsif( $charF eq 'q' ) {
			# - Add the quarter to the output
			#   NOTE: Quarter occupies the month bucket in the hash
			$tempStr = $date{'month'} || '';
			if( $m > length($tempStr) ) {
				$tempStr = '0' . $tempStr;
			} # end if
			$output .= "Q$tempStr";
		} elsif( $charF eq 'm' ) {
			# - Add the month to the output
			if( $m < 3 ) {
				$tempStr = $date{'month'} || '';
				if( $m > length($tempStr) ) {
					$tempStr = '0' . $tempStr;
				} # end if
			} elsif( $m == 3 ) {
				$tempStr = $self->{month_abrev}[$date{'month'} - 1] || '???';
			} else {
				$tempStr = $self->{month_names}[$date{'month'} - 1] || '????';
			} # end if 
			$output .= $tempStr;
		} elsif( $charF eq 'n' ) {
			# - Add the minutes to the output
			$tempStr = $date{'minute'} || '';
			if( $m > length($tempStr) ) {
				$tempStr = '0' . $tempStr;
			} # end if
			$output .= $tempStr;
		} elsif( $charF eq 'd' ) {
			# - Add the day or date to the output
			if( $m < 3 ) {
				$tempStr = $date{day} || '';
				# Remove leading '0' if there is one.
				$tempStr =~ s/^0//g;
				if( $m > length($tempStr) ) {
					$tempStr = '0' . $tempStr;
				} # end if
			} else {
				# - Future implementation of "Thirteenth"
				$tempStr = '';
			} # end if 
			$output .= $tempStr;
		
		} elsif( $charF eq 'w' ) {
			# - Add day of the week to the output, if it's numeric
			if( defined $date{day} ) {
				# If the original date was not a single number, and this is a full date, then
				# calculate the day of the week from the date.
				if( ($date =~ /\D/) && defined $date{month} && defined $date{year} && $date{month} && $date{day} && $date{year} ) {
					# Get the day of the week from the perpetual calendar
					# (Use _nocheck to avoid out of range errors)
					my $y = $date{year};
					$y -= 1900 if $y > 1900;
					$y += 100 if $y < 50;		# Promote 2-digit years < 50 to 2000 - 2050.
					my @t = localtime( Time::Local::timelocal_nocheck( 0, 0, 0, $date{day}, $date{month} - 1, $y ) );
					$tempStr = $t[6];
				} else {
					# Day of the week is in the 'day' bucket [0 - 6]
					$tempStr = $date{day};
				} # end if
				if( $tempStr =~ /^\d+$/ ) {
					if( $m < 4 ) {
						$tempStr = substr( $self->{day_abrev}[$tempStr], 0, $m );
					} else {
						$tempStr = $self->{day_names}[$tempStr];
					} # end if 
				} # end if
				$output .= $tempStr;
			} # end if
			
		} elsif( $charF eq 'h' ) {
			# - Add the hour to the output
			$tempStr = $date{hour} || '';
			if( (index($format, 'am') != -1) || (index($format, 'pm') != -1) ) {
				# Convert to 12-hour format
				my $h12;
				if( $date{hour} == 0 ) {
					$h12 = 12;
				} elsif( $date{hour} < 12 ) {
					$h12 = $date{hour};
				} elsif( $date{hour} == 12 ) {
					$h12 = 12;
				} else {
					$h12 = $date{hour} - 12;
				} # end if 
				$tempStr = $h12;
			} # end if 
			if( $m > length($tempStr) ) {
				$tempStr = '0' . $tempStr;
			} # end if
			$output .= $tempStr;

		} elsif( $charF eq 's' ) {
			# - Add the seconds to the output
			$tempStr = $date{'second'} || '';
			if( $m > length($tempStr) ) {
				$tempStr = '0' . $tempStr;
			} # end if
			$output .= $tempStr;

		} elsif( ($charF eq 'a') || ($charF eq 'p') ) {
			# - Add am or pm to the output
			if( substr( $format, $posF, 1 ) eq 'm' ) {
				$posF++;
				# Am or Pm specifier
				if( $date{'hour'} < 12 )  {
					$tempStr .= 'AM';
				} else {
					$tempStr .= 'PM';
				} # end if
				if( substr( $format, $posF - 2, 1 ) eq substr( $caseFormat, $posF, 1 ) ) {
					# Original was lower case
					$tempStr = lc( $tempStr );
				} # end if
				$output .= $tempStr;
			} else {
				$output .= $charF;
			} # end if 

		} else {
			# - Just send the uninterpreted character along to the output
			while( $m-- ) {
				$output .= $charF;
			} # end if
		} # end if
		
	} # end while 

	return $output;
	
} # end formatDate




# ----------------------------------------------------------
# Sub: getDateString
#
# Args: @dateCols
#	@dateCols	A list of date values in order y,m,d,h,n
#
# Description: Returns a standard date from a set of columns.
#              This formats the the date in yyyy/mm/dd hh:nn.
#              Formatting is specific in @datetime, below.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 1999Feb24 Create function                               JW
# ----------------------------------------------------------
sub getDateString {
	my $self = shift;
	my( @dateCols ) = @_;
	my @datetime = ( '', '/', '/', ' ', ':', ' ', ' ' );
	my $i = $#dateCols;
	my $pointName = pop( @dateCols );

	while( $i > 0 ) {
		$pointName = pop( @dateCols ) . $datetime[$i] . $pointName;
		$i--;
	} # end while

	return $pointName;
} # end getDateString




# ----------------------------------------------------------
# Sub: formatMessage
#
# Args: $format, @args
#	$format	A message string with %0, %1, %2.. replacement points
#	@args  	The strings to insert in the message
#
# Description: A message formatter that replaces each %0, %1, 
# %2 with the argument at that index. If the argument is in 
# the form of %{0:date:yyyy}, then argument 0 is formatted 
# as a date with format 'yyyy'. Also supports type 'number',
# with number format string and the keyword 'integer' as a 
# number format.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000Apr11 Added header appended to first use            JW
# 2000Apr11 Added prefix appended to each use             JW
# 2000Jul06 Removed header and prefix.                    JW
# 2001Jan20 Added ability to format dates && numbers      JW
# 2001Jan26 Changed %{0:type:fmt} to use format_value     JW
# 30Aug2001 Cleaned up some warnings                      JW
# 07Oct2001 Cleaned more warnings when $args[$1] == undef JW
# 21Nov2001 Fixed bug where '0' evaluated to ''           JW
# 17Jan2002 Fixed same 0 -> '' bug for second regexp      JW
# ----------------------------------------------------------
sub formatMessage {
	my $self = shift;
	my($format, @args) = @_;
	@args = () if @args == 0;		# In case there are no args given?
	
	my $tmp;
	$format =~ s/\%\{(\d+)\:([^\}]+)\}/$tmp = $self->format_value($2,defined $args[$1] ? $args[$1] : ''); defined $tmp ? $tmp : ''/ge;
	$format =~ s/\%(\d+)/defined $args[$1] ? $args[$1] : ''/ge;

	return $format;
} # end formatMessage




# ----------------------------------------------------------
# Sub: formatNumber
#
# Args: $fmt, $num
#	$fmt  The format to apply to the number
#	$num	The number to format
#
# Description: Formats a number according to the current 
# localizations. Rounds to decimal_digits, formats with 
# decimal_sep and num_sep. Uses pecent when requested and 
# applies a number format if given.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created by Corey Kaye / DNS                   CK
# 1999Apr10 Modified for internationalization             JW
# 2000May07 Added support for a number format spec        JW
# 2001Jan20 Supports format without decimals and rounds   JW
# 2001Jan26 Added integer, percent, and currency formats  JW
# 30Aug2001 Cleaned up some warnings                      JW
# 26Jul2002 Converted to sprintf for better rounding      JW
# 04Feb2003 Patched more warnings for integral numbers    JW
# 20Mar2003 Changed exists on array for 5.005 compat'ty   JW
# ----------------------------------------------------------
sub formatNumber {
	my $self = shift;
	my $lsep = $self->{'number_sep'};
	my $dsep = $self->{'decimal_sep'};
	my $ddig = $self->{'decimal_digits'};
	my $fmt;

	# Get input number and format
	( $fmt, $_) = @_;

	# Don't do anything if no number to format
	return $_ unless defined $_;
	return undef unless /^\d/;
	
	if( defined $fmt ) {
		# Convert keywords:
		$fmt = '#.#%' if $fmt eq 'percent';
		$fmt = '#' if $fmt eq 'integer';
		$fmt = '$#.#' if $fmt eq 'currency';
	
		# Adjust decimal digits to format if specified.
		# A format like '#.#' makes no change. One like 
		# '#.#0' sets decimal digits to 2.
		# A format without a '.' has no decimal part.
		my $d = index( $fmt, '.' );
		my $z = rindex( $fmt, '0' );
		if( ($z > 0) && ($d > 0) && ($z > $d) ) {
			$ddig = ($z - $d);
		} # end if
		if( $d == -1 ) {
			$ddig = 0;
		} # end if;
	} # end if

	# Find decimal point and limit to number of digits
	if( $ddig > 0 ) {
		$_ = sprintf( "%.${ddig}f", $_ );
	} else {
		$_ = sprintf( "%d", $_ );
	} # end if
	my @temp = split( /\./, $_, 2 );

	# Left pad to any number of '0' before '.'
	if( defined $fmt ) {
		my $d = index( $fmt, '.' );
		my $z = index( $fmt, '0' );
		my $pad = 0;
		if( ($d > 0) && ($z > 0) && ($z < $d) ) {
			$pad = $d - $z;
		} else {
			#** Not sure why this is here????
			#$d = rindex( $fmt, '0' );
			#$pad = $d - $z + 1;
		} # end if
		$pad -= length( $temp[0] );
		$temp[0] = '0' x $pad . $temp[0];
	} # end if

	# Add list separator every 3 digits
	# -- Yeah this is ugly perl wizardy, but 
	#    it's really damn fast! (18% speed increase)
	my $counter = 0;
	my $formattedNumber = join( '', reverse( map { ($counter++ % 3) == 0 ? $_ . $lsep : $_ } reverse( split //, $temp[0] ) ) );

	# Clean number of the extra $lsep on the end
	# -- If $lSep is blank, then there's no last digit. Also, 
	#    if $lSep is more than one char (is this ever true?) then 
	#    this takes care of them all.
	$formattedNumber = substr( $formattedNumber, 0, length($formattedNumber) - length($lsep) );

	# Restore the decimal portion, if any
	$formattedNumber .= "$dsep$temp[1]" if @temp == 2  && $temp[1] ne '';

	# Apply prefix and suffix from format, if any
	if( defined $fmt ) {
		if( $fmt =~ /\./ ) {
			$fmt =~ s/^([^\#0]*)[\#0]*\.[\#0]*([^\#0]*)$/$1$formattedNumber$2/;
		} else {
			$fmt =~ s/^([^\#0]*)[\#0]*([^\#0]*)$/$1$formattedNumber$2/;
		} # end if
		$formattedNumber = $fmt if $fmt ne '';
	} # end if

	# Internationalize the percent symbol, if one
	my $percent = $self->{percent};
	$formattedNumber =~ s/\%/$percent/;

	# Internationalize the currency symbol, if one
	my $currency = $self->{currency};
	$formattedNumber =~ s/\$/$currency/;

	return $formattedNumber;
} # end formatNumber



# ----------------------------------------------------------
# Sub: format_period
#
# Args: $format, $value
#	$format  The format for the time elements. May be empty.
#	$value   The value to format as a period (in seconds)
#
# Description: Formats a length of seconds into length of 
# time (period / duration).
# The format string may contain text and values to be used to 
# display the period. The syntax for the format is any of %d, 
# %h, %m, and %s is replaced with the days, hours, minutes and 
# seconds.
# If no format is given then the current locale settings are
# used to construct a phrase with all of the elements.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2001Jan26 Created method                                JW
# 2001Jan29 Added support for ranges                      JW
# 21Nov2001 Caught warnings on empty value                JW
# ----------------------------------------------------------
sub format_period {
	my $self = shift;
	my( $format, $value ) = @_;

	# If it's blank, just return it
	return $value if !defined($value) || ($value eq '');
	
	
	# If there's no format string us the locale one
	$format = $self->{period_string} unless $format;

	# If it's a range value then just return the value of the range
	# Any '0' value in a range is given a unit nonetheless
	#     *** This is not internationalized!!!
	#... could support a list of ranges...
	if( $value =~ /([\d\.]+)\s*-\s*([\d\.]+)/ ) {
		my( $f, $l ) = ($1, $2);
		if( $f == 0 ) {
			my $f2 = $self->format_period( $format, 2 );
			$f2 =~ s/2/$f/;
			$f = $f2;
		} else {
			$f = $self->format_period( $format, $f );
		} # end if
		if( $l == 0 ) {
			my $l2 = $self->format_period( $format, 2 );
			$l2 =~ s/2/$l/;
			$l = $l2;
		} else {
			$l = $self->format_period( $format, $l );
		} # end if
		$value =~ s/([\d\.]+)(\s*-\s*)([\d\.]+)/$f$2$l/;
		return $value;
	} # end if
	
	#** Future implementation if needed
	# 	if( $format =~ /\%y/ ) {
	# 		my $y = int( $value / 31536000 );
	# 		$value -= 31536000 * $y;
	# 		$format =~ s/\%y/$y/;
	# 	} # end if
	# 
	# 	if( $format =~ /\%w/ ) {
	# 		my $w = int( $value / 604800 );
	# 		$value -= 604800 * $w;
	# 		$format =~ s/\%w/$w/;
	# 	} # end if

	if( $format =~ /\%\{?d/ ) {
		my $d = int( $value / 86400 );
		$value -= 86400 * $d;
		if( $format =~ /\%d/ ) {
			$format =~ s/\%d/$d/g;
		} else {
			$format =~ s/\%\{d\:([^\}]+)\}/$self->format_value($1,$d)/ge
		} # end if
	} # end if

	if( $format =~ /\%\{?h/ ) {
		my $h = int( $value / 3600 );
		$value -= 3600 * $h;
		if( $format =~ /\%h/ ) {
			$format =~ s/\%h/$h/g;
		} else {
			$format =~ s/\%\{h\:([^\}]+)\}/$self->format_value($1,$h)/ge
		} # end if
	} # end if

	if( $format =~ /\%\{?m/ ) {
		my $m = int( $value / 60 );
		$value -= 60 * $m;
		if( $format =~ /\%m/ ) {
			$format =~ s/\%m/$m/g;
		} else {
			$format =~ s/\%\{m\:([^\}]+)\}/$self->format_value($1,$m)/ge
		} # end if
	} # end if

	if( $format =~ /\%\{?s/ ) {
		if( $format =~ /\%s/ ) {
			$format =~ s/\%s/$value/g;
		} else {
			$format =~ s/\%\{s\:([^\}]+)\}/$self->format_value($1,$value)/ge
		} # end if
	} # end if

	return $format;
} # end format_period

# ----------------------------------------------------------
# Sub: format_bytes
#
# Args: $format, $value [, $as]
#	$format  Ignored. Used for compatibility with other format functions
#	$value   The value to format as bytes
#	$as      (Optional) forces formatting as a particular size (e.g. 'M')
#
# Description: Formats a number of bytes into kb, MB, GB, etc.
# If $value include the units 'bytes' or 'b' that
# is removed before localization.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2001Jan26 Created method                                JW
# 21Nov2001 Caught warnings on empty value                JW
# 26Jul2002 Fixed bug in decimal values and rounding      JW
# 26Jul2002 Added internationalization of number          JW
# 26Nov2002 Added $as for specific formatting level       JW
# ----------------------------------------------------------
sub format_bytes {
	my $self = shift;
	my( $f, $value, $as ) = @_;
	$value =~ s/[^\d\.]//g;

	# If it's blank, just return it
	return $value if !defined($value) || ($value eq '');

	# Get $as value if not numeric into a numeric power of 1024
	if( defined($as) && $as =~ /\D/ ) {
		my $cnt = scalar @{$self->{byte_pref}};
		while( $cnt ) {
			if( $self->{byte_pref}[$cnt -1] eq $as ) {
				$as = $cnt - 1;
				last;
			} # end if
			$cnt--
		} # end if
	} # end if

	#
	# If we are doing a format $as then only divide by that value
	# otherwise find the largest integral divisor and use that
	#
	my $pref;
	if( defined($as) and ($as !~ /\D/) ) {
		$pref = $self->{byte_pref}[$as];
		$value = sprintf( "%.3f", $value / (1024 ** ($as + 1)) );
	} else {
		# Start from the end of the byte_pref array and count down portions
		my $cnt = scalar @{$self->{byte_pref}};
		while( $cnt ) {
			my $n = 1024**$cnt;
			if( $value >= $n ) {
				$value = sprintf( "%.3f", $value / $n );
				$pref = $self->{byte_pref}[$cnt - 1];
				last;
			} # end if
			$cnt--
		} # end if
	} # end if
	
	return $self->formatMessage( 
		$self->{bytes}, 
		$self->formatNumber( '#.000', $value ),
		$pref
	);
} # end format_bytes

# ----------------------------------------------------------
# Sub: format_bps
#
# Args: $format, $value
#	$format  Ignored. Used for compatibility with other format functions
#	$value   The value to format as a network rate (bps)
#
# Description: Formats a rate of bps into kbps, Mbps, Gbps, 
# etc. If the value contains the 'bps' units that is removed
# before localization.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2001Jan26 Created method                                JW
# 21Nov2001 Caught warnings on empty value                JW
# 26Jul2002 Fixed bug in decimal values and rounding      JW
# 26Jul2002 Added internationalization of number          JW
# ----------------------------------------------------------
sub format_bps {
	my $self = shift;
	my( $f, $value ) = @_;
	$value =~ s/[^\d\.]//g;

	# If it's blank, just return it
	return $value if !defined($value) || ($value eq '');

	# Start from the end of the byte_pref array and count down portions
	my $cnt = scalar @{$self->{byte_pref}};
	my $pref;
	while( $cnt ) {
		my $n = 1024**$cnt;
		if( $value >= $n ) {
			$value = sprintf( "%.3f", $value / $n );
			$pref = $self->{byte_pref}[$cnt - 1];
			last;
		} # end if
		$cnt--
	} # end if
	
	return $self->formatMessage( 
		$self->{bps}, 
		$self->formatNumber( '#.000', $value ),
		$pref
	);
} # end format_bps


# ----------------------------------------------------------
# Sub: format_choice
#
# Args: $format, $value
#	$format  The choice format string. See below
#	$value   The value to format as bytes
#
# Description: Formats a number of bytes into kb, MB, GB, etc.
# If the value to format include the units 'bytes' or 'b' that
# is removed before localization.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2001Jan27 Created method                                JW
# ----------------------------------------------------------
sub format_choice {
	my $self = shift;
	my( $format, $value ) = @_;
	my( @keys, @values );
	my $choice;
	$value ||= 0;
	
	foreach( split( /\|/, $format ) ) {
		my( $k, $v ) = /^([^\#]+)\#(.*)$/;
		push @keys, $k;
		push @values, $v;
	} # end foreach

	# Find @key where $key[j] <= $value < $key[j+1]
	my $i;
	for( $i = 0; $i < (@keys - 1); $i++ ) {
		if( ($keys[$i] == $value) || (($keys[$i] < $value) && ($value < $keys[$i+1])) ) {
			$choice = $values[$i];
			last;
		} # end if
	} # end for
	$choice = $values[$#keys] if $value == $keys[$#keys];
	
	# If no key, then look below and above
	unless( defined $choice ) {
		if( $value < $keys[0] ) {
			$choice = $values[0];
		} elsif( $value > $keys[$#keys] ) {
			$choice = $values[$#keys];
		} # end if
	} # end unless
	
	$choice =~ s/\%\{0\:([^\}]+)\}/$self->format_value($1,$value)/ge;
	$choice =~ s/\%0/$value/g;
		
	return $choice;
} # end format_choice


# ----------------------------------------------------------
# Sub: getPercent
#
# Args: $pages, $total
#	$pages	The number of items to count
#	$total	The total number of which $pages is a percent
#
# Description: Returns a localized, formatted value for 
#              the percent of $pages in $total.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
#           Created by Corey Kay / DNS                    CK
# 1999Jun11 Modified to use a localizations               JW
# ----------------------------------------------------------
sub getPercent {
	my $self = shift;
	my ($pages, $total) = @_;
	my $percent;
	my $dsep = $self->{'decimal_sep'};
	my $ddig = $self->{'decimal_digits'};
	my $percentFloor;
	my $percentDec = '';

	for( 1..$ddig ) {
		$percentDec .= '0';
	} # end while
	
	if( $total > 0 ) {
		$percent = $pages / $total * 100;

		if ($percent > 99.9) { 
			$percentFloor = '100';
		} else {
			$percentFloor = $percent;
			$percentFloor =~ s/^(\d+).*/$1/;
			$percent =~ s/^\d+.(\d{0,$ddig}).*/$1/;
			if( length( $percent ) == $ddig ) {
				$percentDec = $percent;
			} # end if
		} # end if

		$percent = $percentFloor . $dsep . $percentDec;
	} else {
		$percent = '--';
	} # end if
	
	return $percent;
	
} # end getPercent


# ----------------------------------------------------------
# Sub: split_date
#
# Args: $date $hashRef
#	$date   	A date in the (Analog) format of yyyy/mm/dd hh:mm
#	$hashRef	A hashRef that gets the values assoc'd with names
#
# Description: Given a data and hash ref, splits out the 
#              components of the date and stores them in the 
#              hash associated with filed names "year", "month", 
#              "day", "hour" and "minute" and "second".
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 12Jun2001 Returns false if not a valid date             JW
# 14Jun2001 Improved speed with split()                   JW
# ----------------------------------------------------------
sub split_date {
	my $self = shift;
	my( $date, $hashRef ) = @_;
	# If it's not a valid date-like string then return undef (false)
	return undef unless defined $date;
	return undef unless $date =~ /\d/;
	
	my @d = split( /\D+/, $date );
	$hashRef->{year} = $d[0] if defined $d[0];
	$hashRef->{month} = $d[1] if defined $d[1];
	$hashRef->{day} = $d[2] if defined $d[2];
	$hashRef->{hour} = $d[3] if defined $d[3];
	$hashRef->{minute} = $d[4] if defined $d[4];
	$hashRef->{second} = $d[5] if defined $d[5];
	
	return @d;	# A valid date returns true
} # end split_date


##########################
##                      ##
##   Private Methods    ##
##                      ##
##########################


# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds
