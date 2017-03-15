"""an extended chroot equivalent"""

from __future__ import absolute_import, unicode_literals

import argparse
import errno
from functools import partial
import os
import sys

from pychroot.base import Chroot
from pychroot.exceptions import ChrootError

from snakeoil.cli import arghparse


def bindmount(s, recursive=False, readonly=False):
    opts = {'recursive': recursive, 'readonly': readonly}
    return {s: opts}


class mountpoints(argparse.Action):

    def __call__(self, parser, namespace, values, option_string=None):
        if not getattr(namespace, 'mountpoints', False):
            namespace.mountpoints = {}
        namespace.mountpoints.update(values)


argparser = arghparse.ArgumentParser(
    color=False, debug=False, quiet=False, verbose=False,
    description=__doc__)
argparser.add_argument('path', help='path to newroot')
argparser.add_argument(
    'command', nargs=argparse.REMAINDER, help='optional command to run',
    docs="""
        Optional command to run.

        Similar to chroot(1), if unspecified this defaults to $SHELL from the
        host environment and if that's unset it executes /bin/sh.
    """)
argparser.add_argument(
    '--no-mounts', action='store_true',
    help='disable the default bind mounts',
    docs="""
        Disable the default bind mounts which can be used to obtain a standard
        chroot environment that you'd expect when using chroot(1).
    """)
argparser.add_argument(
    '--hostname', type=str, help='specify the chroot hostname',
    docs="""
        Specify the chroot hostname. In order to set the domain name as well,
        pass an FQDN instead of a singular hostname.
    """)
argparser.add_argument(
    '--skip-chdir', action='store_true',
    help="do not change working directory to '/'",
    docs="""
        Do not change the current working directory to '/'.

        Unlike chroot(1), this currently doesn't limit you to only using it
        when the new root isn't '/'. In other words, you can use a new chroot
        environment on the current host system rootfs with one caveat: any
        absolute paths will use the new rootfs.
    """)
argparser.add_argument(
    '-B', '--bind', type=bindmount, action=mountpoints,
    metavar='SRC[:DEST]', help='specify custom bind mount',
    docs="""
        Specify a custom bind mount.

        In order to mount the same source to multiple destinations, use the
        SRC:DEST syntax. For example, the following will bind mount '/srv/data'
        to /srv/data and /home/user/data in the chroot::

            pychroot -B /srv/data -B /srv/data:/home/user/data /path/to/chroot
    """)
argparser.add_argument(
    '-R', '--rbind', type=partial(bindmount, recursive=True),
    action=mountpoints, metavar='SRC[:DEST]',
    help='specify custom recursive bind mount')

argparser.add_argument(
    '--ro', '--readonly', type=partial(bindmount, readonly=True),
    action=mountpoints, metavar='SRC[:DEST]',
    help='specify custom readonly bind mount',
    docs="""
        Specify a custom readonly bind mount.

        Readonly, recursive bind mounts aren't currently supported on Linux so
        this has to be a standalone option for now. Once they are, support for
        them and other mount attributes will be added as an extension to the
        mount point argument syntax.
    """)


def parse_args(args):
    opts = argparser.parse_args(args)

    if not opts.command:
        opts.command = [os.getenv('SHELL', '/bin/sh'), '-i']

    if not hasattr(opts, 'mountpoints'):
        opts.mountpoints = None

    if opts.no_mounts:
        Chroot.default_mounts = {}

    return opts


def main(args):
    opts = parse_args(args)

    try:
        with Chroot(opts.path, mountpoints=opts.mountpoints,
                    hostname=opts.hostname, skip_chdir=opts.skip_chdir):
            os.execvp(opts.command[0], opts.command)
    except EnvironmentError as e:
        if (e.errno == errno.ENOENT):
            raise SystemExit(
                "{}: failed to run command '{}': {}".format(
                    os.path.basename(sys.argv[0]), opts.command[0], e.strerror))
        raise
    except ChrootError as e:
        raise SystemExit('{}: {}'.format(os.path.basename(sys.argv[0]), str(e)))
