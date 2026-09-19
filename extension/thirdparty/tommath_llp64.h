/* LibTomMath 0.42 gives every __x86_64__ build 60-bit digits typed unsigned long, which is 32 bits on Windows. */
#ifndef WOWDOT_TOMMATH_LLP64_H
#define WOWDOT_TOMMATH_LLP64_H

#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#undef __x86_64__
#include <tommath.h>
#define __x86_64__ 1

#endif
