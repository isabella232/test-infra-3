#!/bin/bash
# Copyright 2018 The Kubernetes Authors.
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

CACHE_BUCKET="jetstack-bazel-cache"
CACHE_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-}"

# get the installed version of a debian package
package_to_version () {
    dpkg-query --showformat='${Version}' --show $1
}

# look up a binary with which and return the debian package it belongs to
command_to_package () {
    local binary_path=$(readlink -f $(which $1))
    # `dpkg -S $package` spits out lines with the format: "package: file"
    dpkg -S $1 | grep "${binary_path}" | cut -d':' -f1
}

# get the installed package version relating to a binary
command_to_version () {
    local package=$(command_to_package $1)
    package_to_version "${package}"
}

hash_toolchains () {
    # if $CC is set bazel will use this to detect c/c++ toolchains, otherwise gcc
    # https://blog.bazel.build/2016/03/31/autoconfiguration.html
    local cc="${CC:-gcc}"
    local cc_version=$(command_to_version $cc)
    # NOTE: IIRC some rules call python internally, this can't hurt
    local python_version=$(command_to_version python)
    # combine all tool versions into a hash
    # NOTE(bentheelder): if we change the set of tools considered we should
    # consider prepending the hash with a """schema version""" for completeness
    local tool_versions="CC:${cc_version},PY:{python_version}"
    echo "${tool_versions}" | md5sum | cut -d" " -f1
}

get_workspace () {
    # get org/repo from prow, otherwise use $PWD
    if [[ -n "${REPO_NAME}" ]] && [[ -n "${REPO_OWNER}" ]]; then
        echo "${REPO_OWNER}/${REPO_NAME}"
    else
        echo "$(basename $(dirname $PWD))/$(basename $PWD)"
    fi
}

make_bazel_rc () {
    # this is the default for recent releases but we set it explicitly
    # since this is the only hash our cache supports
    echo "startup --host_jvm_args=-Dbazel.DigestFunction=sha256"
    # use remote caching for all the things
    echo "build --experimental_remote_spawn_cache"
    # don't fail if the cache is unavailable
    echo "build --remote_local_fallback"
    # point bazel at our http cache ...
    # NOTE our caches are versioned by all path segments up until the last two
    # IE PUT /foo/bar/baz/cas/asdf -> is in cache "/foo/bar/baz"
    local cache_id="$(get_workspace),$(hash_toolchains)"
    local cache_url="https://storage.googleapis.com/${CACHE_BUCKET}/${cache_id}"
    echo "build --remote_http_cache=${cache_url}"
    echo "build --google_credentials=${CACHE_CREDENTIALS}"
}

# https://docs.bazel.build/versions/master/user-manual.html#bazelrc
# bazel will look for two RC files, taking the first option in each set of paths
# firstly:
# - The path specified by the --bazelrc=file startup option. If specified, this option must appear before the command name (e.g. build)
# - A file named .bazelrc in your base workspace directory
# - A file named .bazelrc in your home directory
make_bazel_rc >> "${HOME}/.bazelrc"
# Aside from the optional configuration file described above, Bazel also looks for a master rc file next to the binary, in the workspace at tools/bazel.rc or system-wide at /etc/bazel.bazelrc.
# These files are here to support installation-wide options or options shared between users. Reading of this file can be disabled using the --nomaster_bazelrc option.
make_bazel_rc >> "/etc/bazel.bazelrc"
# hopefully no repos create *both* of these ...
