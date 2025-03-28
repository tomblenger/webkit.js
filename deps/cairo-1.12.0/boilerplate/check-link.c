#define CAIRO_VERSION_H 1

#include <cairo-boilerplate.h>

/* get the "real" version info instead of dummy cairo-version.h */
#undef CAIRO_VERSION_H
#include "../cairo-version.h"

#include <stdio.h>

#ifndef TARGET_EMSCRIPTEN
int
main (void)
{
  printf ("Check linking to the just built cairo boilerplate library\n");
  if (cairo_boilerplate_version () == CAIRO_VERSION) {
    return 0;
  } else {
    fprintf (stderr,
	     "Error: linked to cairo boilerplate version %s instead of %s\n",
	     cairo_boilerplate_version_string (),
	     CAIRO_VERSION_STRING);
    return 1;
  }
}
#endif