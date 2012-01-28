############################################################
#
# Module: wadg::Errors.pm
#
# This is a static class to provide global references 
# to fatal and non-fatal messaging services.
#
# Created: 25.Apr.2000 by Jeremy Wadsack for Wadsack-Allen Digital Group
# Copyright (C) 2000,2002 Wadsack-Allen. All rights reserved.
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
############################################################
# Date        Modification                            Author
# ----------------------------------------------------------
############################################################
package wadg::Errors;

use strict;

BEGIN {
	use vars       qw($VERSION @ISA);


	$VERSION = do { my @r = (q$Revision: 2.20 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

	@ISA         = qw();
} # end BEGIN

# Package globals are here
use vars      qw( $WARNING $ERROR );

###########################
##                       ##
## Public Static Methods ##
##                       ##
###########################
# ----------------------------------------------------------
# Sub: set_error_handler
#
# Args: $code_ref
#	$code_ref	A code reference to an error handler routine
#
# Description: Stores the $code_ref as the class-wide error
# handler
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000APR25 Created class method                          JW
# ----------------------------------------------------------
sub set_error_handler {
	my( $code_ref ) = @_;

	$ERROR = $code_ref;
	
	return $code_ref;
} # end set_error_handler


# ----------------------------------------------------------
# Sub: set_warning_handler
#
# Args: $code_ref
#	$code_ref	A code reference to a warning handler routine
#
# Description: Stores the $code_ref as the class-wide handler
# for warnings
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000APR25 Created class method                          JW
# ----------------------------------------------------------
sub set_warning_handler {
	my( $code_ref ) = @_;

	$WARNING = $code_ref;
	
	return $code_ref;
} # end set_warning_handler

# ----------------------------------------------------------
# Sub: error
#
# Args: @list
#	@list	A list of parameters to send to the error handler
#
# Description: Throws a fatal error exception through the 
# installed handler with the specified list of parameters
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000APR25 Created class method                          JW
# ----------------------------------------------------------
sub error {
	my( @list ) = @_;

	# Probably shouldn't return, but just in case
	return &$ERROR( @list ) if defined $ERROR;

	# if $ERROR isn't installed, use Perl's
	die( @list );
} # end error

# ----------------------------------------------------------
# Sub: warning
#
# Args: @list
#	@list	A list of parameters to send to the warning handler
#
# Description: Throws a non-fatal warning exception through 
# the installed handler with the specified list of parameters
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 2000APR25 Created class method                          JW
# ----------------------------------------------------------
sub warning {
	my( @list ) = @_;

	return &$WARNING( @list ) if defined $WARNING;

	# if $WARINING isn't installed, use Perl's
	return warn( @list );
} # end error

# ----------------------------------------------------------
# Sub: stack_trace
#
# Args: $frame
#	$frame  The frame to start with (defaults to 0)
#
# Returns: Trace as a scalar string
#
# Description: Produces a stack trace from the calling method
# and returns it as a string. Helpful in debugging. If $frame
# is provided then it will skip $frame frames before starting
# the stack trace (for example, to call stack_trace from an 
# error_handler you may wish to provide a $frame of 1). This
# method will never trace more than 100 frames deep.
# ----------------------------------------------------------
# Date      Modification                              Author
# ----------------------------------------------------------
# 06May2001 Added for generalized debugging               JW
# 14Aug2001 Fixed minor display bugs                      JW
# ----------------------------------------------------------
sub stack_trace {
	my( $level ) = @_;
	$level ||= 0;
	my $trace = '';
	
	my @fields = caller($level);
	$trace .= "Stack trace: called from $fields[1] line $fields[2]\n";
	for( ($level + 1) .. 100 ) {
		@fields = caller($_);
		last unless @fields;
		$trace .= "             $fields[3] in $fields[1] line $fields[2]\n";
	} # end for

	return $trace;
} # end stack_trace

# module clean-up code here (global destructor)
END { }

1;  # so the require or use succeeds

