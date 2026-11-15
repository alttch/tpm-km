#!/usr/bin/python3
"""Canonical rootfs manifest. Never imports or executes code from measured root."""
import hashlib
import json
import os
import stat
import sys

def manifest(root, rules):
    rootfd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    result = {}
    def record(path):
        if path in result:
            return
        parts = path.strip("/").split("/")
        if not path.startswith("/") or any(p in ("", ".", "..") for p in parts):
            raise ValueError("unsafe monitored path: " + path)
        parent = os.dup(rootfd)
        try:
            for component in parts[:-1]:
                child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                os.close(parent)
                parent = child
            try:
                st = os.stat(parts[-1], dir_fd=parent, follow_symlinks=False)
            except FileNotFoundError:
                result[path] = ["missing"]
                return
            info = [stat.S_IFMT(st.st_mode), stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid]
            leaf = "/proc/self/fd/%d/%s" % (parent, parts[-1])
            # l*xattr on a pinned parent: do not follow a leaf symlink.
            info.append([[n, os.getxattr(leaf, n, follow_symlinks=False).hex()]
                         for n in sorted(os.listxattr(leaf, follow_symlinks=False))])
            if stat.S_ISLNK(st.st_mode):
                info.append(os.readlink(parts[-1], dir_fd=parent))
                result[path] = info
            elif stat.S_ISREG(st.st_mode):
                fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
                try:
                    before = os.fstat(fd)
                    if (before.st_dev, before.st_ino, before.st_mode) != (st.st_dev, st.st_ino, st.st_mode):
                        raise ValueError("file changed during scan")
                    h = hashlib.sha256()
                    while True:
                        chunk = os.read(fd, 1024 * 1024)
                        if not chunk:
                            break
                        h.update(chunk)
                    after = os.fstat(fd)
                    if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                        raise ValueError("file changed during scan")
                    info.extend([after.st_size, h.hexdigest()])
                    result[path] = info
                finally:
                    os.close(fd)
            elif stat.S_ISDIR(st.st_mode):
                fd = os.open(parts[-1], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                try:
                    names = sorted(os.listdir(fd))
                finally:
                    os.close(fd)
                result[path] = info + [names]
                for name in names:
                    record(path + "/" + name)
            else:
                raise ValueError("unsupported file type: " + path)
        except FileNotFoundError:
            result[path] = ["missing"]
        finally:
            os.close(parent)
    try:
        paths = sorted(set(l.strip() for l in rules.splitlines() if l.strip() and not l.lstrip().startswith("#")))
        for p in paths:
            record(p)
        body = ["tpm-km-rootfs-v1", paths, [[p, result[p]] for p in sorted(result)]]
        return json.dumps(body, ensure_ascii=True, separators=(",", ":")).encode()
    finally:
        os.close(rootfd)

if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("usage: tpm-km-manifest.py ROOT RULES")
        with open(sys.argv[2], encoding="utf-8") as f:
            rules = f.read()
        print(hashlib.sha256(manifest(sys.argv[1], rules)).hexdigest())
    except Exception as exc:
        print("tpm-km manifest: " + str(exc), file=sys.stderr)
        sys.exit(1)
