/* Block-relocating memory allocator. 
   Copyright (C) 1992 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 1, or (at your option)
any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs; see the file COPYING.  If not, write to
the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.  */

/* NOTES:

   Only relocate the blocs neccessary for SIZE in r_alloc_sbrk,
   rather than all of them.  This means allowing for a possible
   hole between the first bloc and the end of malloc storage. */

#ifdef emacs
#include "config.h"
#include "lisp.h"		/* Needed for VALBITS.  */

/* Declared in dispnew.c, this version doesn't screw up if regions
   overlap.  */
extern void safe_bcopy ();
#endif

#ifndef emacs
#include <stddef.h>
typedef size_t SIZE;
typedef void *POINTER;
#define EXCEEDS_LISP_PTR(x) 0

#define safe_bcopy(x, y, z) memmove (y, x, z)
#endif

#undef NULL
#include "mem_limits.h"
#include "getpagesize.h"

#define NIL ((POINTER) 0)

/* A flag to indicate whether we have initialized ralloc yet.  For
   Emacs's sake, please do not make this local to malloc_init; on some
   machines, the dumping procedure makes all static variables
   read-only.  On these machines, the word static is #defined to be
   the empty string, meaning that r_alloc_initialized becomes an
   automatic variable, and loses its value each time Emacs is started up.  */
static int r_alloc_initialized = 0;

static void r_alloc_init ();

/* Declarations for working with the malloc, ralloc, and system breaks.  */

/* System call to set the break value. */
extern POINTER sbrk ();

/* The break value, as seen by malloc (). */
static POINTER virtual_break_value;

/* The break value, viewed by the relocatable blocs. */
static POINTER break_value;

/* The REAL (i.e., page aligned) break value of the process. */
static POINTER page_break_value;

/* Macros for rounding.  Note that rounding to any value is possible
   by changing the definition of PAGE. */
#define PAGE (getpagesize ())
#define ALIGNED(addr) (((unsigned int) (addr) & (PAGE - 1)) == 0)
#define ROUNDUP(size) (((unsigned int) (size) + PAGE - 1) & ~(PAGE - 1))
#define ROUND_TO_PAGE(addr) (addr & (~(PAGE - 1)))

/* Managing "almost out of memory" warnings.  */

/* Level of warnings issued. */
static int warnlevel;

/* Function to call to issue a warning;
   0 means don't issue them.  */
static void (*warn_function) ();

static void
check_memory_limits (address)
     POINTER address;
{
  SIZE data_size = address - data_space_start;
  int five_percent = lim_data / 20;

  switch (warnlevel)
    {
    case 0: 
      if (data_size > five_percent * 15)
	{
	  warnlevel++;
	  (*warn_function) ("Warning: past 75% of memory limit");
	}
      break;

    case 1: 
      if (data_size > five_percent * 17)
	{
	  warnlevel++;
	  (*warn_function) ("Warning: past 85% of memory limit");
	}
      break;

    case 2: 
      if (data_size > five_percent * 19)
	{
	  warnlevel++;
	  (*warn_function) ("Warning: past 95% of memory limit");
	}
      break;

    default:
      (*warn_function) ("Warning: past acceptable memory limits");
      break;
    }

  /* If we go down below 70% full, issue another 75% warning
     when we go up again.  */
  if (data_size < five_percent * 14)
    warnlevel = 0;
  /* If we go down below 80% full, issue another 85% warning
     when we go up again.  */
  else if (warnlevel > 1 && data_size < five_percent * 16)
    warnlevel = 1;
  /* If we go down below 90% full, issue another 95% warning
     when we go up again.  */
  else if (warnlevel > 2 && data_size < five_percent * 18)
    warnlevel = 2;

  if (EXCEEDS_LISP_PTR (address))
    memory_full ();
}

/* Functions to get and return memory from the system.  */

/* Obtain SIZE bytes of space.  If enough space is not presently available
   in our process reserve, (i.e., (page_break_value - break_value)),
   this means getting more page-aligned space from the system.

   Return non-zero if all went well, or zero if we couldn't allocate
   the memory.  */
static int
obtain (size)
     SIZE size;
{
  SIZE already_available = page_break_value - break_value;

  if (already_available < size)
    {
      SIZE get = ROUNDUP (size - already_available);

      if (warn_function)
	check_memory_limits (page_break_value);

      if (((int) sbrk (get)) < 0)
	return 0;

      page_break_value += get;
    }

  break_value += size;

  return 1;
}

/* Obtain SIZE bytes of space and return a pointer to the new area.
   If we could not allocate the space, return zero.  */

static POINTER
get_more_space (size)
     SIZE size;
{
  POINTER ptr = break_value;
  if (obtain (size))
    return ptr;
  else
    return 0;
}

/* Note that SIZE bytes of space have been relinquished by the process.
   If SIZE is more than a page, return the space to the system. */

static void
relinquish (size)
     SIZE size;
{
  POINTER new_page_break;

  break_value -= size;
  new_page_break = (POINTER) ROUNDUP (break_value);
  
  if (new_page_break != page_break_value)
    {
      if (((int) (sbrk ((char *) new_page_break
			- (char *) page_break_value))) < 0)
	abort ();

      page_break_value = new_page_break;
    }

  /* Zero the space from the end of the "official" break to the actual
     break, so that bugs show up faster.  */
  bzero (break_value, ((char *) page_break_value - (char *) break_value));
}

/* The meat - allocating, freeing, and relocating blocs.  */

/* These structures are allocated in the malloc arena.
   The linked list is kept in order of increasing '.data' members.
   The data blocks abut each other; if b->next is non-nil, then
   b->data + b->size == b->next->data.  */
typedef struct bp
{
  struct bp *next;
  struct bp *prev;
  POINTER *variable;
  POINTER data;
  SIZE size;
} *bloc_ptr;

#define NIL_BLOC ((bloc_ptr) 0)
#define BLOC_PTR_SIZE (sizeof (struct bp))

/* Head and tail of the list of relocatable blocs. */
static bloc_ptr first_bloc, last_bloc;

/* Find the bloc referenced by the address in PTR.  Returns a pointer
   to that block. */

static bloc_ptr
find_bloc (ptr)
     POINTER *ptr;
{
  register bloc_ptr p = first_bloc;

  while (p != NIL_BLOC)
    {
      if (p->variable == ptr && p->data == *ptr)
	return p;

      p = p->next;
    }

  return p;
}

/* Allocate a bloc of SIZE bytes and append it to the chain of blocs.
   Returns a pointer to the new bloc, or zero if we couldn't allocate
   memory for the new block.  */

static bloc_ptr
get_bloc (size)
     SIZE size;
{
  register bloc_ptr new_bloc;

  if (! (new_bloc = (bloc_ptr) malloc (BLOC_PTR_SIZE))
      || ! (new_bloc->data = get_more_space (size)))
    {
      if (new_bloc)
	free (new_bloc);

      return 0;
    }

  new_bloc->size = size;
  new_bloc->next = NIL_BLOC;
  new_bloc->variable = (POINTER *) NIL;

  if (first_bloc)
    {
      new_bloc->prev = last_bloc;
      last_bloc->next = new_bloc;
      last_bloc = new_bloc;
    }
  else
    {
      first_bloc = last_bloc = new_bloc;
      new_bloc->prev = NIL_BLOC;
    }

  return new_bloc;
}

/* Relocate all blocs from BLOC on upward in the list to the zone
   indicated by ADDRESS.  Direction of relocation is determined by
   the position of ADDRESS relative to BLOC->data.

   Note that ordering of blocs is not affected by this function. */

static void
relocate_some_blocs (bloc, address)
     bloc_ptr bloc;
     POINTER address;
{
  register bloc_ptr b;
  POINTER data_zone = bloc->data;
  register SIZE data_zone_size = 0;
  register SIZE offset = bloc->data - address;
  POINTER new_data_zone = data_zone - offset;

  for (b = bloc; b != NIL_BLOC; b = b->next)
    {
      data_zone_size += b->size;
      b->data -= offset;
      *b->variable = b->data;
    }

  safe_bcopy (data_zone, new_data_zone, data_zone_size);
}

/* Free BLOC from the chain of blocs, relocating any blocs above it
   and returning BLOC->size bytes to the free area. */

static void
free_bloc (bloc)
     bloc_ptr bloc;
{
  if (bloc == first_bloc && bloc == last_bloc)
    {
      first_bloc = last_bloc = NIL_BLOC;
    }
  else if (bloc == last_bloc)
    {
      last_bloc = bloc->prev;
      last_bloc->next = NIL_BLOC;
    }
  else if (bloc == first_bloc)
    {
      first_bloc = bloc->next;
      first_bloc->prev = NIL_BLOC;
      relocate_some_blocs (bloc->next, bloc->data);
    }
  else
    {
      bloc->next->prev = bloc->prev;
      bloc->prev->next = bloc->next;
      relocate_some_blocs (bloc->next, bloc->data);
    }

  relinquish (bloc->size);
  free (bloc);
}

/* Interface routines.  */

static int use_relocatable_buffers;

/* Obtain SIZE bytes of storage from the free pool, or the system, as
   necessary.  If relocatable blocs are in use, this means relocating
   them.  This function gets plugged into the GNU malloc's __morecore
   hook.

   If we're out of memory, we should return zero, to imitate the other
   __morecore hook values - in particular, __default_morecore in the
   GNU malloc package.  */

POINTER 
r_alloc_sbrk (size)
     long size;
{
  POINTER ptr;

  if (! use_relocatable_buffers)
    return sbrk (size);

  if (size > 0)
    {
      if (! obtain (size))
	return 0;

      if (first_bloc)
	{
	  relocate_some_blocs (first_bloc, first_bloc->data + size);

	  /* Zero out the space we just allocated, to help catch bugs
	     quickly.  */
	  bzero (virtual_break_value, size);
	}
    }
  else if (size < 0)
    {
      if (first_bloc)
        relocate_some_blocs (first_bloc, first_bloc->data + size);
      relinquish (- size);
    }

  ptr = virtual_break_value;
  virtual_break_value += size;
  return ptr;
}

/* Allocate a relocatable bloc of storage of size SIZE.  A pointer to
   the data is returned in *PTR.  PTR is thus the address of some variable
   which will use the data area.

   If we can't allocate the necessary memory, set *PTR to zero, and
   return zero.  */

POINTER
r_alloc (ptr, size)
     POINTER *ptr;
     SIZE size;
{
  register bloc_ptr new_bloc;

  if (! r_alloc_initialized)
    r_alloc_init ();

  new_bloc = get_bloc (size);
  if (new_bloc)
    {
      new_bloc->variable = ptr;
      *ptr = new_bloc->data;
    }
  else
    *ptr = 0;

  return *ptr;
}

/* Free a bloc of relocatable storage whose data is pointed to by PTR.
   Store 0 in *PTR to show there's no block allocated.  */

void
r_alloc_free (ptr)
     register POINTER *ptr;
{
  register bloc_ptr dead_bloc;

  dead_bloc = find_bloc (ptr);
  if (dead_bloc == NIL_BLOC)
    abort ();

  free_bloc (dead_bloc);
  *ptr = 0;
}

/* Given a pointer at address PTR to relocatable data, resize it to SIZE.
   Do this by shifting all blocks above this one up in memory, unless
   SIZE is less than or equal to the current bloc size, in which case
   do nothing.

   Change *PTR to reflect the new bloc, and return this value.

   If more memory cannot be allocated, then leave *PTR unchanged, and
   return zero.  */

POINTER
r_re_alloc (ptr, size)
     POINTER *ptr;
     SIZE size;
{
  register bloc_ptr bloc;

  bloc = find_bloc (ptr);
  if (bloc == NIL_BLOC)
    abort ();

  if (size <= bloc->size)
    /* Wouldn't it be useful to actually resize the bloc here?  */
    return *ptr;

  if (! obtain (size - bloc->size))
    return 0;

  relocate_some_blocs (bloc->next, bloc->data + size);

  /* Zero out the new space in the bloc, to help catch bugs faster.  */
  bzero (bloc->data + bloc->size, size - bloc->size);

  /* Indicate that this block has a new size.  */
  bloc->size = size;

  return *ptr;
}

/* The hook `malloc' uses for the function which gets more space
   from the system.  */
extern POINTER (*__morecore) ();

/* Intialize various things for memory allocation. */

static void
r_alloc_init ()
{
  if (r_alloc_initialized)
    return;

  r_alloc_initialized = 1;
  __morecore = r_alloc_sbrk;

  virtual_break_value = break_value = sbrk (0);
  if (break_value == (POINTER)NULL)
    abort ();
#if 0 /* The following is unreasonable because warn_func may be 0.  */
    (*warn_func)("memory initialization got 0 from sbrk(0).");
#endif

  page_break_value = (POINTER) ROUNDUP (break_value);
  /* Clear the rest of the last page; this memory is in our address space
     even though it is after the sbrk value.  */
  bzero (break_value, (page_break_value - break_value));
  use_relocatable_buffers = 1;

  lim_data = 0;
  warnlevel = 0;

  get_lim_data ();
}

/* This is the name Emacs expects to call.  */

void
memory_warnings (start, warn_func)
     POINTER start;
     void (*warn_func) ();
{
  if (start)
    data_space_start = start;
  else
    data_space_start = start_of_data ();

  warn_function = warn_func;
}
