.. 
   Copyright (C) Internet Systems Consortium, Inc. ("ISC")
   
   This Source Code Form is subject to the terms of the Mozilla Public
   License, v. 2.0. If a copy of the MPL was not distributed with this
   file, you can obtain one at https://mozilla.org/MPL/2.0/.
   
   See the COPYRIGHT file distributed with this work for additional
   information regarding copyright ownership.

Notes for BIND 9.17.10
----------------------

Security Fixes
~~~~~~~~~~~~~~

- None.

Known Issues
~~~~~~~~~~~~

- None.

New Features
~~~~~~~~~~~~

- None.

Removed Features
~~~~~~~~~~~~~~~~

- A number of non-working configuration options that had been marked
  as obsolete in previous releases have now been removed completely.
  Using any of the following options is now considered a configuration
  failure:
  ``acache-cleaning-interval``, ``acache-enable``, ``additional-from-auth``,
  ``additional-from-cache``, ``allow-v6-synthesis``, ``cleaning-interval``,
  ``dnssec-enable``, ``dnssec-lookaside``, ``filter-aaaa``,
  ``filter-aaaa-on-v4``, ``filter-aaaa-on-v6``, ``geoip-use-ecs``, ``lwres``,
  ``max-acache-size``, ``nosit-udp-size``, ``queryport-pool-ports``,
  ``queryport-pool-updateinterval``, ``request-sit``, ``sit-secret``,
  ``support-ixfr``, ``use-queryport-pool``, ``use-ixfr``. [GL #1086]

Feature Changes
~~~~~~~~~~~~~~~

- The default value of ``max-stale-ttl`` has been changed from 12 hours to 1
  day and the default value of ``stale-answer-ttl`` has been changed from 1
  second to 30 seconds, following RFC 8767 recommendations. [GL #2248]

Bug Fixes
~~~~~~~~~

- KASP incorrectly set signature validity to the value of the DNSKEY signature
  validity. This is now fixed. [GL #2383]
