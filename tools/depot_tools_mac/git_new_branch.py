#!/usr/bin/env python
# Copyright 2014 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import argparse
import sys

import subprocess2

from git_common import run, root, set_config, get_or_create_merge_base, tags
from git_common import hash_one


def main(args):
  parser = argparse.ArgumentParser(
    formatter_class=argparse.ArgumentDefaultsHelpFormatter
  )
  parser.add_argument('branch_name')
  g = parser.add_mutually_exclusive_group()
  g.add_argument('--upstream_current', action='store_true',
                 help='set upstream branch to current branch.')
  g.add_argument('--upstream', metavar='REF', default=root(),
                 help='upstream branch (or tag) to track.')
  g.add_argument('--lkgr', action='store_const', const='lkgr', dest='upstream',
                 help='set basis ref for new branch to lkgr.')

  opts = parser.parse_args(args)

  try:
    if opts.upstream_current:
      run('checkout', '--track', '-b', opts.branch_name)
    else:
      if opts.upstream in tags():
        # TODO(iannucci): ensure that basis_ref is an ancestor of HEAD?
        run('checkout', '--no-track', '-b', opts.branch_name,
            hash_one(opts.upstream))
        set_config('branch.%s.remote' % opts.branch_name, '.')
        set_config('branch.%s.merge' % opts.branch_name, opts.upstream)
      else:
        # TODO(iannucci): Detect unclean workdir then stash+pop if we need to
        # teleport to a conflicting portion of history?
        run('checkout', '--track', opts.upstream, '-b', opts.branch_name)

    get_or_create_merge_base(opts.branch_name)
  except subprocess2.CalledProcessError as cpe:
    sys.stdout.write(cpe.stdout)
    sys.stderr.write(cpe.stderr)
    return 1


if __name__ == '__main__':  # pragma: no cover
  sys.exit(main(sys.argv[1:]))
