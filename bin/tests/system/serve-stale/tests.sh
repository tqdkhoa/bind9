#!/bin/sh
#
# Copyright (C) Internet Systems Consortium, Inc. ("ISC")
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, you can obtain one at https://mozilla.org/MPL/2.0/.
#
# See the COPYRIGHT file distributed with this work for additional
# information regarding copyright ownership.

. ../conf.sh

RNDCCMD="$RNDC -c ../common/rndc.conf -p ${CONTROLPORT} -s"
DIG="$DIG +time=11"

max_stale_ttl=$(sed -ne 's,^[[:space:]]*max-stale-ttl \([[:digit:]]*\).*,\1,p' $TOP_SRCDIR/bin/named/config.c)
stale_answer_ttl=$(sed -ne 's,^[[:space:]]*stale-answer-ttl \([[:digit:]]*\).*,\1,p' $TOP_SRCDIR/bin/named/config.c)

status=0
n=0

#
# First test server with serve-stale options set.
#
echo_i "test server with serve-stale options set"

n=$((n+1))
echo_i "prime cache longttl.example ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 longttl.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache data.example ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache othertype.example ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 othertype.example CAA > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nodata.example ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 nodata.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nxdomain.example ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 nxdomain.example TXT > dig.out.test$n
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify prime cache statistics ($n)"
ret=0
rm -f ns1/named.stats
$RNDCCMD 10.53.0.1 stats > /dev/null 2>&1
[ -f ns1/named.stats ] || ret=1
cp ns1/named.stats ns1/named.stats.$n
# Check first 10 lines of Cache DB statistics.  After prime queries, we expect
# two active TXT, one active Others, one nxrrset TXT, and one NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns1/named.stats.$n > ns1/named.stats.$n.cachedb || ret=1
grep "1 Others" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "2 TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 !TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 NXDOMAIN" ns1/named.stats.$n.cachedb > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "disable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt disable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"0\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: on (stale-answer-ttl=4 max-stale-ttl=3600 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

sleep 2

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.1 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.1 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.1 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check stale data.example ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*4.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Run rndc dumpdb, test whether the stale data has correct comment printed.
# The max-stale-ttl is 3600 seconds, so the comment should say the data is
# stale for somewhere between 3500-3599 seconds.
echo_i "check rndc dump stale data.example ($n)"
rndc_dumpdb ns1 || ret=1
awk '/; stale/ { x=$0; getline; print x, $0}' ns1/named_dump.db.test$n |
    grep "; stale (will be retained for 35.. more seconds) data\.example.*A text record with a 2 second ttl" > /dev/null 2>&1 || ret=1
# Also make sure the not expired data does not have a stale comment.
awk '/; answer/ { x=$0; getline; print x, $0}' ns1/named_dump.db.test$n |
    grep "; answer longttl\.example.*A text record with a 600 second ttl" > /dev/null 2>&1 || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale othertype.example ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "othertype\.example\..*4.*IN.*CAA.*0.*issue" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nodata.example ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*4.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nxdomain.example ($n)"
ret=0
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*4.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify stale cache statistics ($n)"
ret=0
rm -f ns1/named.stats
$RNDCCMD 10.53.0.1 stats > /dev/null 2>&1
[ -f ns1/named.stats ] || ret=1
cp ns1/named.stats ns1/named.stats.$n
# Check first 10 lines of Cache DB statistics.  After serve-stale queries, we
# expect one active TXT RRset, one stale TXT, one stale nxrrset TXT, and one
# stale NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns1/named.stats.$n > ns1/named.stats.$n.cachedb || ret=1
grep "1 TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #Others" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #!TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #NXDOMAIN" ns1/named.stats.$n.cachedb > /dev/null || ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

# Test stale-refresh-time when serve-stale is enabled via configuration.
# Steps for testing stale-refresh-time option (default).
# 1. Prime cache data.example txt
# 2. Disable responses from authoritative server.
# 3. Sleep for TTL duration so rrset TTL expires (2 sec)
# 4. Query data.example
# 5. Check if response come from stale rrset (3 sec TTL)
# 6. Enable responses from authoritative server.
# 7. Query data.example
# 8. Check if response come from stale rrset, since the query
#    is within stale-refresh-time window.
n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: on (stale-answer-ttl=4 max-stale-ttl=3600 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 1-3 done above.

# Step 4.
n=$((n+1))
echo_i "sending query for test ($n)"
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$n

# Step 5.
echo_i "check stale data.example (stale-refresh-time) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*4.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 6.
n=$((n+1))
echo_i "enable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt enable > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 7.
echo_i "sending query for test $((n+1))"
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1))

# Step 8.
n=$((n+1))
echo_i "check stale data.example comes from cache (stale-refresh-time) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*4.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

#
# Test disabling serve-stale via rndc.
#
n=$((n+1))
echo_i "disable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt disable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"0\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "running 'rndc serve-stale off' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale off || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: off (rndc) (stale-answer-ttl=4 max-stale-ttl=3600 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.1 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.1 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.1 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check stale data.example (serve-stale off) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale othertype.example (serve-stale off) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nodata.example (serve-stale off) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nxdomain.example (serve-stale off) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

#
# Test enabling serve-stale via rndc.
#
n=$((n+1))
echo_i "running 'rndc serve-stale on' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale on || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: on (rndc) (stale-answer-ttl=4 max-stale-ttl=3600 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.1 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.1 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.1 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check stale data.example (serve-stale on) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*4.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale othertype.example (serve-stale on) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "othertype\.example\..*4.*IN.*CAA.*0.*issue" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nodata.example (serve-stale on) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*4.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nxdomain.example (serve-stale on) ($n)"
ret=0
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*4.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "running 'rndc serve-stale off' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale off || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "running 'rndc serve-stale reset' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale reset || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: on (stale-answer-ttl=4 max-stale-ttl=3600 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.1 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.1 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.1 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check stale data.example (serve-stale reset) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*4.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale othertype.example (serve-stale reset) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "othertype.example\..*4.*IN.*CAA.*0.*issue" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nodata.example (serve-stale reset) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*4.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nxdomain.example (serve-stale reset) ($n)"
ret=0
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*4.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "running 'rndc serve-stale off' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale off || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: off (rndc) (stale-answer-ttl=4 max-stale-ttl=3600 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

#
# Update named.conf.
# Test server with low max-stale-ttl.
#
echo_i "test server with serve-stale options set, low max-stale-ttl"

n=$((n+1))
echo_i "updating ns1/named.conf ($n)"
ret=0
copy_setports ns1/named2.conf.in ns1/named.conf
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "running 'rndc reload' ($n)"
ret=0
rndc_reload ns1 10.53.0.1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: off (rndc) (stale-answer-ttl=3 max-stale-ttl=20 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "flush cache, re-enable serve-stale and query again ($n)"
ret=0
$RNDCCMD 10.53.0.1 flushtree example > rndc.out.test$n.1 2>&1 || ret=1
$RNDCCMD 10.53.0.1 serve-stale on > rndc.out.test$n.2 2>&1 || ret=1
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$n
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: on (rndc) (stale-answer-ttl=3 max-stale-ttl=20 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "enable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt enable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache longttl.example (low max-stale-ttl) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 longttl.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache data.example (low max-stale-ttl) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache othertype.example (low max-stale-ttl) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 othertype.example CAA > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nodata.example (low max-stale-ttl) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 nodata.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nxdomain.example (low max-stale-ttl) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 nxdomain.example TXT > dig.out.test$n
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# keep track of time so we can access these rrset later,
# when we expect them to become ancient.
t1=`$PERL -e 'print time()'`

n=$((n+1))
echo_i "verify prime cache statistics (low max-stale-ttl) ($n)"
ret=0
rm -f ns1/named.stats
$RNDCCMD 10.53.0.1 stats > /dev/null 2>&1
[ -f ns1/named.stats ] || ret=1
cp ns1/named.stats ns1/named.stats.$n
# Check first 10 lines of Cache DB statistics.  After prime queries, we expect
# two active TXT RRsets, one active Others, one nxrrset TXT, and one NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns1/named.stats.$n > ns1/named.stats.$n.cachedb || ret=1
grep "2 TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 Others" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 !TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 NXDOMAIN" ns1/named.stats.$n.cachedb > /dev/null || ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

n=$((n+1))
echo_i "disable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt disable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"0\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

sleep 2

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.1 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.1 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.1 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check stale data.example (low max-stale-ttl) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*3.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale othertype.example (low max-stale-ttl) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "othertype\.example\..*3.*IN.*CAA.*0.*issue" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nodata.example (low max-stale-ttl) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*3.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check stale nxdomain.example (low max-stale-ttl) ($n)"
ret=0
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*3.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify stale cache statistics (low max-stale-ttl) ($n)"
ret=0
rm -f ns1/named.stats
$RNDCCMD 10.53.0.1 stats > /dev/null 2>&1
[ -f ns1/named.stats ] || ret=1
cp ns1/named.stats ns1/named.stats.$n
# Check first 10 lines of Cache DB statistics.  After serve-stale queries, we
# expect one active TXT RRset, one stale TXT, one stale nxrrset TXT, and one
# stale NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns1/named.stats.$n > ns1/named.stats.$n.cachedb || ret=1
grep "1 TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #Others" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #!TXT" ns1/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #NXDOMAIN" ns1/named.stats.$n.cachedb > /dev/null || ret=1

status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

# retrieve max-stale-ttl value,
interval_to_ancient=`grep 'max-stale-ttl' ns1/named2.conf.in  | awk '{ print $2 }' | tr -d ';'`
# we add 2 seconds to it since this is the ttl value of the records being tested.
interval_to_ancient=$((interval_to_ancient + 2))
t2=`$PERL -e 'print time()'`
elapsed=$((t2 - t1))

# if elapsed time so far is less than max-stale-ttl + 2 seconds,
# then we sleep enough to ensure that we'll ask for ancient rrsets
# in the next queries.
if [ $elapsed -lt $interval_to_ancient ]; then
    sleep $((interval_to_ancient - elapsed))
fi

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.1 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.1 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.1 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check ancient data.example (low max-stale-ttl) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check ancient othertype.example (low max-stale-ttl) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check ancient nodata.example (low max-stale-ttl) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check ancient nxdomain.example (low max-stale-ttl) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Test stale-refresh-time when serve-stale is enabled via rndc.
# Steps for testing stale-refresh-time option (default).
# 1. Prime cache data.example txt
# 2. Disable responses from authoritative server.
# 3. Sleep for TTL duration so rrset TTL expires (2 sec)
# 4. Query data.example
# 5. Check if response come from stale rrset (3 sec TTL)
# 6. Enable responses from authoritative server.
# 7. Query data.example
# 8. Check if response come from stale rrset, since the query
#    is within stale-refresh-time window.
n=$((n+1))
echo_i "flush cache, enable responses from authoritative server ($n)"
ret=0
$RNDCCMD 10.53.0.1 flushtree example > rndc.out.test$n.1 2>&1 || ret=1
$DIG -p ${PORT} @10.53.0.2 txt enable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: on (rndc) (stale-answer-ttl=3 max-stale-ttl=20 stale-refresh-time=30)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 1.
n=$((n+1))
echo_i "prime cache data.example (stale-refresh-time rndc) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*2.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 2.
n=$((n+1))
echo_i "disable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt disable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"0\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 3.
sleep 2

# Step 4.
n=$((n+1))
echo_i "sending query for test ($n)"
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$n

# Step 5.
echo_i "check stale data.example (stale-refresh-time rndc) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*3.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 6.
n=$((n+1))
echo_i "enable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt enable > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 7.
echo_i "sending query for test $((n+1))"
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1))

# Step 8.
n=$((n+1))
echo_i "check stale data.example comes from cache (stale-refresh-time rndc) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*3.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Steps for testing stale-refresh-time option (disabled).
# 1. Prime cache data.example txt
# 2. Disable responses from authoritative server.
# 3. Sleep for TTL duration so rrset TTL expires (2 sec)
# 4. Query data.example
# 5. Check if response come from stale rrset (3 sec TTL)
# 6. Enable responses from authoritative server.
# 7. Query data.example
# 8. Check if response come from stale rrset, since the query
#    is within stale-refresh-time window.
n=$((n+1))
echo_i "updating ns1/named.conf ($n)"
ret=0
copy_setports ns1/named3.conf.in ns1/named.conf
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "running 'rndc reload' ($n)"
ret=0
rndc_reload ns1 10.53.0.1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.1 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep '_default: on (rndc) (stale-answer-ttl=3 max-stale-ttl=20 stale-refresh-time=0)' rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "flush cache, enable responses from authoritative server ($n)"
ret=0
$RNDCCMD 10.53.0.1 flushtree example > rndc.out.test$n.1 2>&1 || ret=1
$DIG -p ${PORT} @10.53.0.2 txt enable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 1.
n=$((n+1))
echo_i "prime cache data.example (stale-refresh-time disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*2.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 2.
n=$((n+1))
echo_i "disable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt disable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"0\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 3.
sleep 2

# Step 4.
n=$((n+1))
echo_i "sending query for test ($n)"
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$n

# Step 5.
echo_i "check stale data.example (stale-refresh-time disabled) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*3.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 6.
n=$((n+1))
echo_i "enable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt enable > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Step 7.
echo_i "sending query for test $((n+1))"
$DIG -p ${PORT} @10.53.0.1 data.example TXT > dig.out.test$((n+1))

# Step 8.
n=$((n+1))
echo_i "check stale data.example comes from authoritative (stale-refresh-time disabled) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*2.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

#
# Now test server with no serve-stale options set.
#
echo_i "test server with no serve-stale options set"

n=$((n+1))
echo_i "enable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt enable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache longttl.example (max-stale-ttl default) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.3 longttl.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache data.example (max-stale-ttl default) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.3 data.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*2.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache othertype.example (max-stale-ttl default) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.3 othertype.example CAA > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "othertype\.example\..*2.*IN.*CAA.*0.*issue" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nodata.example (max-stale-ttl default) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.3 nodata.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*2.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nxdomain.example (max-stale-ttl default) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.3 nxdomain.example TXT > dig.out.test$n
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*2.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify prime cache statistics (max-stale-ttl default) ($n)"
ret=0
rm -f ns3/named.stats
$RNDCCMD 10.53.0.3 stats > /dev/null 2>&1
[ -f ns3/named.stats ] || ret=1
cp ns3/named.stats ns3/named.stats.$n
# Check first 10 lines of Cache DB statistics.  After prime queries, we expect
# two active TXT RRsets, one active Others, one nxrrset TXT, and one NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns3/named.stats.$n > ns3/named.stats.$n.cachedb || ret=1
grep "2 TXT" ns3/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 Others" ns3/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 !TXT" ns3/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 NXDOMAIN" ns3/named.stats.$n.cachedb > /dev/null || ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

n=$((n+1))
echo_i "disable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt disable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"0\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.3 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep "_default: off (stale-answer-ttl=$stale_answer_ttl max-stale-ttl=$max_stale_ttl stale-refresh-time=30)" rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

sleep 2

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.3 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.3 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.3 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.3 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check fail of data.example (max-stale-ttl default) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of othertype.example (max-stale-ttl default) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of nodata.example (max-stale-ttl default) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of nxdomain.example (max-stale-ttl default) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify stale cache statistics (max-stale-ttl default) ($n)"
ret=0
rm -f ns3/named.stats
$RNDCCMD 10.53.0.3 stats > /dev/null 2>&1
[ -f ns3/named.stats ] || ret=1
cp ns3/named.stats ns3/named.stats.$n
# Check first 10 lines of Cache DB statistics. After last queries, we expect
# one active TXT RRset, one stale TXT, one stale nxrrset TXT, and one
# stale NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns3/named.stats.$n > ns3/named.stats.$n.cachedb || ret=1
grep "1 TXT" ns3/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #TXT" ns3/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #Others" ns3/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #!TXT" ns3/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #NXDOMAIN" ns3/named.stats.$n.cachedb > /dev/null || ret=1

status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

n=$((n+1))
echo_i "check 'rndc serve-stale on' ($n)"
ret=0
$RNDCCMD 10.53.0.3 serve-stale on > rndc.out.test$n 2>&1 || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.3 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep "_default: on (rndc) (stale-answer-ttl=$stale_answer_ttl max-stale-ttl=$max_stale_ttl stale-refresh-time=30)" rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

sleep 2

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.3 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.3 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.3 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.3 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check data.example (max-stale-ttl default) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*30.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check othertype.example (max-stale-ttl default) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "example\..*30.*IN.*CAA.*0.*issue" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check nodata.example (max-stale-ttl default) ($n)"
ret=0
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*30.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check nxdomain.example (max-stale-ttl default) ($n)"
ret=0
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*30.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

#
# Now test server with serve-stale answers disabled.
#
echo_i "test server with serve-stale disabled"

n=$((n+1))
echo_i "enable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt enable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache longttl.example (serve-stale answers disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.4 longttl.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache data.example (serve-stale answers disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.4 data.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*2.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache othertype.example (serve-stale answers disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.4 othertype.example CAA > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "othertype\.example\..*2.*IN.*CAA.*0.*issue" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nodata.example (serve-stale answers disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.4 nodata.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*2.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nxdomain.example (serve-stale answers disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.4 nxdomain.example TXT > dig.out.test$n
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*2.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify prime cache statistics (serve-stale answers disabled) ($n)"
ret=0
rm -f ns4/named.stats
$RNDCCMD 10.53.0.4 stats > /dev/null 2>&1
[ -f ns4/named.stats ] || ret=1
cp ns4/named.stats ns4/named.stats.$n
# Check first 10 lines of Cache DB statistics.  After prime queries, we expect
# two active TXT RRsets, one active Others, one nxrrset TXT, and one NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns4/named.stats.$n > ns4/named.stats.$n.cachedb || ret=1
grep "2 TXT" ns4/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 Others" ns4/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 !TXT" ns4/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 NXDOMAIN" ns4/named.stats.$n.cachedb > /dev/null || ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

n=$((n+1))
echo_i "disable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt disable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"0\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.4 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep "_default: off (stale-answer-ttl=$stale_answer_ttl max-stale-ttl=$max_stale_ttl stale-refresh-time=30)" rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

sleep 2

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.4 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.4 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.4 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.4 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check fail of data.example (serve-stale answers disabled) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of othertype.example (serve-stale answers disabled) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of nodata.example (serve-stale answers disabled) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of nxdomain.example (serve-stale answers disabled) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify stale cache statistics (serve-stale answers disabled) ($n)"
ret=0
rm -f ns4/named.stats
$RNDCCMD 10.53.0.4 stats > /dev/null 2>&1
[ -f ns4/named.stats ] || ret=1
cp ns4/named.stats ns4/named.stats.$n
# Check first 10 lines of Cache DB statistics. After last queries, we expect
# one active TXT RRset, one stale TXT, one stale nxrrset TXT, and one
# stale NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns4/named.stats.$n > ns4/named.stats.$n.cachedb || ret=1
grep "1 TXT" ns4/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #TXT" ns4/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #Others" ns4/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #!TXT" ns4/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 #NXDOMAIN" ns4/named.stats.$n.cachedb > /dev/null || ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

# Dump the cache.
n=$((n+1))
echo_i "dump the cache (serve-stale answers disabled) ($n)"
ret=0
rndc_dumpdb ns4 -cache || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

echo_i "stop ns4"
$PERL ../stop.pl --use-rndc --port ${CONTROLPORT} serve-stale ns4

# Load the cache as if it was five minutes (RBTDB_VIRTUAL) older.
# Since max-stale-ttl defaults to a week, we need to adjust the date by
# one week and five minutes.
LASTWEEK=`TZ=UTC perl -e 'my $now = time();
        my $oneWeekAgo = $now - 604800;
        my $fiveMinutesAgo = $oneWeekAgo - 300;
        my ($s, $m, $h, $d, $mo, $y) = (localtime($fiveMinutesAgo))[0, 1, 2, 3, 4, 5];
        printf("%04d%02d%02d%02d%02d%02d", $y+1900, $mo+1, $d, $h, $m, $s);'`

echo_i "mock the cache date to $LASTWEEK (serve-stale answers disabled) ($n)"
ret=0
sed -E "s/DATE [0-9]{14}/DATE $LASTWEEK/g" ns4/named_dump.db.test$n > ns4/named_dump.db.out || ret=1
cp ns4/named_dump.db.out ns4/named_dump.db
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

echo_i "start ns4"
start_server --noclean --restart --port ${PORT} serve-stale ns4

n=$((n+1))
echo_i "verify ancient cache statistics (serve-stale answers disabled) ($n)"
ret=0
rm -f ns4/named.stats
$RNDCCMD 10.53.0.4 stats #> /dev/null 2>&1
[ -f ns4/named.stats ] || ret=1
cp ns4/named.stats ns4/named.stats.$n
# Check first 10 lines of Cache DB statistics. After last queries, we expect
# everything to be removed or scheduled to be removed.
grep -A 10 "++ Cache DB RRsets ++" ns4/named.stats.$n > ns4/named.stats.$n.cachedb || ret=1
grep "#TXT" ns4/named.stats.$n.cachedb > /dev/null && ret=1
grep "#Others" ns4/named.stats.$n.cachedb > /dev/null && ret=1
grep "#!TXT" ns4/named.stats.$n.cachedb > /dev/null && ret=1
grep "#NXDOMAIN" ns4/named.stats.$n.cachedb > /dev/null && ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

#
# Test the server with stale-cache disabled.
#
echo_i "test server with serve-stale cache disabled"

n=$((n+1))
echo_i "enable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt enable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"1\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache longttl.example (serve-stale cache disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.5 longttl.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache data.example (serve-stale cache disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.5 data.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "data\.example\..*2.*IN.*TXT.*A text record with a 2 second ttl" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache othertype.example (serve-stale cache disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.5 othertype.example CAA > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "othertype\.example\..*2.*IN.*CAA.*0.*issue" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nodata.example (serve-stale cache disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.5 nodata.example TXT > dig.out.test$n
grep "status: NOERROR" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*2.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "prime cache nxdomain.example (serve-stale cache disabled) ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.5 nxdomain.example TXT > dig.out.test$n
grep "status: NXDOMAIN" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
grep "example\..*2.*IN.*SOA" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify prime cache statistics (serve-stale cache disabled) ($n)"
ret=0
rm -f ns5/named.stats
$RNDCCMD 10.53.0.5 stats > /dev/null 2>&1
[ -f ns5/named.stats ] || ret=1
cp ns5/named.stats ns5/named.stats.$n
# Check first 10 lines of Cache DB statistics.  After serve-stale queries,
# we expect two active TXT RRsets, one active Others, one nxrrset TXT, and
# one NXDOMAIN.
grep -A 10 "++ Cache DB RRsets ++" ns5/named.stats.$n > ns5/named.stats.$n.cachedb || ret=1
grep "2 TXT" ns5/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 Others" ns5/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 !TXT" ns5/named.stats.$n.cachedb > /dev/null || ret=1
grep "1 NXDOMAIN" ns5/named.stats.$n.cachedb > /dev/null || ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

n=$((n+1))
echo_i "disable responses from authoritative server ($n)"
ret=0
$DIG -p ${PORT} @10.53.0.2 txt disable  > dig.out.test$n
grep "ANSWER: 1," dig.out.test$n > /dev/null || ret=1
grep "TXT.\"0\"" dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check 'rndc serve-stale status' ($n)"
ret=0
$RNDCCMD 10.53.0.5 serve-stale status > rndc.out.test$n 2>&1 || ret=1
grep "_default: off (not-cached)" rndc.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

sleep 2

echo_i "sending queries for tests $((n+1))-$((n+4))..."
$DIG -p ${PORT} @10.53.0.5 data.example TXT > dig.out.test$((n+1)) &
$DIG -p ${PORT} @10.53.0.5 othertype.example CAA > dig.out.test$((n+2)) &
$DIG -p ${PORT} @10.53.0.5 nodata.example TXT > dig.out.test$((n+3)) &
$DIG -p ${PORT} @10.53.0.5 nxdomain.example TXT > dig.out.test$((n+4))

wait

n=$((n+1))
echo_i "check fail of data.example (serve-stale cache disabled) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of othertype.example (serve-stale cache disabled) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of nodata.example (serve-stale cache disabled) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "check fail of nxdomain.example (serve-stale cache disabled) ($n)"
ret=0
grep "status: SERVFAIL" dig.out.test$n > /dev/null || ret=1
grep "ANSWER: 0," dig.out.test$n > /dev/null || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

n=$((n+1))
echo_i "verify stale cache statistics (serve-stale cache disabled) ($n)"
ret=0
rm -f ns5/named.stats
$RNDCCMD 10.53.0.5 stats > /dev/null 2>&1
[ -f ns5/named.stats ] || ret=1
cp ns5/named.stats ns5/named.stats.$n
# Check first 10 lines of Cache DB statistics.  After serve-stale queries,
# we expect one active TXT (longttl) and the rest to be expired from cache,
# but since we keep everything for 5 minutes (RBTDB_VIRTUAL) in the cache
# after expiry, they still show up in the stats.
grep -A 10 "++ Cache DB RRsets ++" ns5/named.stats.$n > ns5/named.stats.$n.cachedb || ret=1
grep -F "1 Others" ns5/named.stats.$n.cachedb > /dev/null || ret=1
grep -F "2 TXT" ns5/named.stats.$n.cachedb > /dev/null || ret=1
grep -F "1 !TXT" ns5/named.stats.$n.cachedb > /dev/null || ret=1
grep -F "1 NXDOMAIN" ns5/named.stats.$n.cachedb > /dev/null || ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

# Dump the cache.
n=$((n+1))
echo_i "dump the cache (serve-stale cache disabled) ($n)"
ret=0
rndc_dumpdb ns5 || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))
# Check that expired records are not dumped.
ret=0
grep "; expired since .* (awaiting cleanup)" ns5/named_dump.db.test$n && ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Dump the cache including expired entries.
n=$((n+1))
echo_i "dump the cache including expired entries (serve-stale cache disabled) ($n)"
ret=0
rndc_dumpdb ns5 -expired || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

# Check that expired records are dumped.
echo_i "check rndc dump expired data.example ($n)"
ret=0
awk '/; expired/ { x=$0; getline; print x, $0}' ns5/named_dump.db.test$n |
    grep "; expired since .* (awaiting cleanup) data\.example\..*A text record with a 2 second ttl" > /dev/null 2>&1 || ret=1
awk '/; expired/ { x=$0; getline; print x, $0}' ns5/named_dump.db.test$n |
    grep "; expired since .* (awaiting cleanup) nodata\.example\." > /dev/null 2>&1 || ret=1
awk '/; expired/ { x=$0; getline; print x, $0}' ns5/named_dump.db.test$n |
    grep "; expired since .* (awaiting cleanup) nxdomain\.example\." > /dev/null 2>&1 || ret=1
awk '/; expired/ { x=$0; getline; print x, $0}' ns5/named_dump.db.test$n |
    grep "; expired since .* (awaiting cleanup) othertype\.example\." > /dev/null 2>&1 || ret=1
# Also make sure the not expired data does not have an expired comment.
awk '/; answer/ { x=$0; getline; print x, $0}' ns5/named_dump.db.test$n |
    grep "; answer longttl\.example.*A text record with a 600 second ttl" > /dev/null 2>&1 || ret=1
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

echo_i "stop ns5"
$PERL ../stop.pl --use-rndc --port ${CONTROLPORT} serve-stale ns5

# Load the cache as if it was five minutes (RBTDB_VIRTUAL) older.
cp ns5/named_dump.db.test$n ns5/named_dump.db
FIVEMINUTESAGO=`TZ=UTC perl -e 'my $now = time();
        my $fiveMinutesAgo = 300;
        my ($s, $m, $h, $d, $mo, $y) = (localtime($fiveMinutesAgo))[0, 1, 2, 3, 4, 5];
        printf("%04d%02d%02d%02d%02d%02d", $y+1900, $mo+1, $d, $h, $m, $s);'`

n=$((n+1))
echo_i "mock the cache date to $FIVEMINUTESAGO (serve-stale cache disabled) ($n)"
ret=0
sed -E "s/DATE [0-9]{14}/DATE $FIVEMINUTESAGO/g" ns5/named_dump.db > ns5/named_dump.db.out || ret=1
cp ns5/named_dump.db.out ns5/named_dump.db
if [ $ret != 0 ]; then echo_i "failed"; fi
status=$((status+ret))

echo_i "start ns5"
start_server --noclean --restart --port ${PORT} serve-stale ns5

n=$((n+1))
echo_i "verify ancient cache statistics (serve-stale cache disabled) ($n)"
ret=0
rm -f ns5/named.stats
$RNDCCMD 10.53.0.5 stats #> /dev/null 2>&1
[ -f ns5/named.stats ] || ret=1
cp ns5/named.stats ns5/named.stats.$n
# Check first 10 lines of Cache DB statistics. After last queries, we expect
# everything to be removed or scheduled to be removed.
grep -A 10 "++ Cache DB RRsets ++" ns5/named.stats.$n > ns5/named.stats.$n.cachedb || ret=1
grep -F "#TXT" ns5/named.stats.$n.cachedb > /dev/null && ret=1
grep -F "#Others" ns5/named.stats.$n.cachedb > /dev/null && ret=1
grep -F "#!TXT" ns5/named.stats.$n.cachedb > /dev/null && ret=1
grep -F "#NXDOMAIN" ns5/named.stats.$n.cachedb > /dev/null && ret=1
status=$((status+ret))
if [ $ret != 0 ]; then echo_i "failed"; fi

echo_i "exit status: $status"
[ $status -eq 0 ] || exit 1
