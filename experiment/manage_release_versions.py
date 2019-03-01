#!/usr/bin/env python

# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

""" This script rotates the version strings in various below listed config files.
Run this script when you want to move the jobs to the new support cadence.

Usage:
    1. update the Version Class below with the appropriate versions.
    2. bazel run //experiment:manage_release_versions
    3. for some config files you may need to make more manual changes. These
    are described as comments before config files are defined below.

"""

import re
import collections

# Probably should just read out of a config file in the future.


class Version(object):
    CURRENT = "1.14" # also known as beta in some other places.
    STABLE1 = "1.13"
    STABLE2 = "1.12"
    STABLE3 = "1.11"
    DEPRECATED = "1.10"

# ordered-dict that keeps the mapping of the rotations.
# we need a ordered dict to make sure we rotate in the
# order of latest to oldest.
RELEASE_VERSION_ROTATION_MAP = collections.OrderedDict([
    (Version.STABLE1, Version.CURRENT),
    (Version.STABLE2, Version.STABLE1),
    (Version.STABLE3, Version.STABLE2),
    (Version.DEPRECATED, Version.STABLE3),
])
# List of job config locations that need version rotation.
# We might have to do more than just rotation in these job configs.
# Assuming that the script is executed from the test-infra root
# directory when run directly.
#

JOB_LIST = [
    "README.md",
    "config/jobs/kubernetes/sig-aws/kops/kops-presubmits.yaml",
    #"config/jobs/kubernetes-security/generated-security-jobs.yaml",
    #"config/jobs/kubernetes/generated/generated.yaml",
    "config/jobs/kubernetes/sig-gcp/gce-conformance.yaml",
    "config/jobs/kubernetes/sig-gcp/gpu/sig-gcp-gpu-presubmit.yaml",
    "config/jobs/kubernetes/sig-gcp/sig-gcp-gce-config.yaml",
    "config/jobs/kubernetes/sig-node/node-kubelet.yaml",
    "config/jobs/kubernetes/sig-node/sig-node-presubmit.yaml",
    "config/jobs/kubernetes/sig-cluster-lifecycle/kubeadm-upgrade.yaml",
    "config/jobs/kubernetes/sig-cluster-lifecycle/kubeadm-x-on-y.yaml",
    "config/jobs/kubernetes/sig-cluster-lifecycle/kubeadm.yaml",
    "config/jobs/kubernetes/sig-scalability/sig-scalability-periodic-jobs.yaml",
    "config/jobs/kubernetes/sig-scalability/sig-scalability-presubmit-jobs.yaml",
    "config/jobs/kubernetes/sig-testing/bazel-build-test.yaml",
    "config/jobs/kubernetes/sig-testing/typecheck.yaml",
    "config/jobs/kubernetes/sig-testing/verify.yaml",
    "experiment/fix_testgrid_config.py",
    "testgrid/config.yaml",
    "scenarios/kubernetes_verify.py",
    # additional changes needs to be made
    # - to make sure versions of dependencies is valid per release.
    # "images/kubekins-e2e/Makefile",
]


def extract_major_minor(version):
    return version.split(".")

def construct_regex(version):
    major, minor = extract_major_minor(version)
    match_regex = r"%s([\.-])%s" % (major, minor)
    major, minor = extract_major_minor(RELEASE_VERSION_ROTATION_MAP[version])
    replace_regex = r"%s\g<1>%s" % (major, minor)
    return (match_regex, replace_regex)

# We are using regular expressions here
# - since the pattern is scattered across the job config
# - pattern repeats into the non-yaml machine readable files.

def main():
    for version in RELEASE_VERSION_ROTATION_MAP:
        match_regex, replace_regex = construct_regex(version)
        for job in JOB_LIST:
            with open(job, 'r') as fp:
                lines = [re.sub(match_regex, replace_regex, line)
                         for line in fp]
            with open(job, 'w') as fp:
                for line in lines:
                    fp.write(line)


if __name__ == "__main__":
    main()
