package Bugzilla::Extension::Push::Constants;

use strict;
use base 'Exporter';

our @EXPORT = qw(
    PUSH_RESULT_OK
    PUSH_RESULT_TRANSIENT
    PUSH_RESULT_ERROR
);

use constant PUSH_RESULT_OK => 1;
use constant PUSH_RESULT_TRANSIENT => 2;
use constant PUSH_RESULT_ERROR => 3;

1;
