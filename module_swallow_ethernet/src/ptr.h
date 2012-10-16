/*
 * ptr - Pointer mangling
 *
 * Copyright (C) 2012 Steve Kerrison <github@stevekerrison.com>
 *
 * This software is freely distributable under a derivative of the
 * University of Illinois/NCSA Open Source License posted in
 * LICENSE.txt and at <http://github.xcore.com/>
 */
 
#ifndef PTR_H
#define PTR_H

#ifdef __XC__
#define PTREF &
#else
#define PTREF *
#endif


#endif //PTR_H
