/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#ifndef __ECO_NL_H
#define __ECO_NL_H

#include <linux/netlink.h>
#include <errno.h>

#include "eco.h"

#define NLMSG_KER_MT "struct eco_nlmsg *ker"

struct eco_nlmsg {
    struct nlmsghdr *nlh;
    struct nlattr *nest;
    int size;
    uint8_t buf[0];
};

static inline int nla_type(const struct nlattr *nla)
{
	return nla->nla_type & NLA_TYPE_MASK;
}

static inline void *nla_data(const struct nlattr *nla)
{
	return (char *)nla + NLA_HDRLEN;
}

static inline int nla_len(const struct nlattr *nla)
{
	return nla->nla_len - NLA_HDRLEN;
}

static inline int nla_ok(const struct nlattr *nla, int remaining)
{
	return remaining >= (int) sizeof(*nla) &&
	       nla->nla_len >= sizeof(*nla) &&
	       nla->nla_len <= remaining;
}

static inline struct nlattr *nla_next(const struct nlattr *nla, int *remaining)
{
	unsigned int totlen = NLA_ALIGN(nla->nla_len);

	*remaining -= totlen;
	return (struct nlattr *)((char *) nla + totlen);
}

#define nla_for_each_attr(pos, head, len, rem) \
	for (pos = head, rem = len; \
	     nla_ok(pos, rem); \
	     pos = nla_next(pos, &(rem)))

#define nla_for_each_nested(pos, nla, rem) \
	nla_for_each_attr(pos, nla_data(nla), nla_len(nla), rem)

#endif
