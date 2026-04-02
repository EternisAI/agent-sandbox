#!/usr/bin/env python3
"""Massive SDK introspection helper for LLM agents.

Usage:
  python3 discover.py methods              # List all methods with signatures
  python3 discover.py method <name>        # Full signature + return model fields for one method
  python3 discover.py model <name>         # All fields and types for a model class
  python3 discover.py models               # List all model classes
  python3 discover.py search <keyword>     # Search methods and models by keyword
"""
import sys
import inspect
import typing
import pkgutil
from massive import RESTClient
import massive.rest.models


def get_all_methods():
    """Return dict of method_name -> (group, method_obj, hints, sig)."""
    methods = {}
    for name in sorted(dir(RESTClient)):
        if name.startswith("_"):
            continue
        attr = getattr(RESTClient, name)
        if not callable(attr):
            continue
        for cls in RESTClient.__mro__:
            if name in cls.__dict__:
                group = cls.__name__.replace("Client", "")
                break
        else:
            group = "Other"
        if group == "Base":
            continue
        try:
            hints = typing.get_type_hints(attr)
            sig = inspect.signature(attr)
        except Exception:
            continue
        methods[name] = (group, attr, hints, sig)
    return methods


def get_all_models():
    """Return dict of 'module.ClassName' -> {field: type_str}."""
    models = {}
    for _, modname, _ in pkgutil.iter_modules(massive.rest.models.__path__):
        if modname in ("request", "common"):
            continue
        mod = __import__(f"massive.rest.models.{modname}", fromlist=[modname])
        for cname, cls in inspect.getmembers(mod, inspect.isclass):
            if not cls.__module__.startswith("massive.rest.models"):
                continue
            ann = {}
            for c in reversed(cls.__mro__):
                ann.update(getattr(c, "__annotations__", {}))
            if ann:
                fields = {}
                for fname, ftype in ann.items():
                    t = str(ftype)
                    t = t.replace("typing.Optional[", "").replace("typing.", "").rstrip("]")
                    t = t.replace("<class '", "").replace("'>", "")
                    fields[fname] = t
                models[f"{modname}.{cname}"] = fields
    return models


def format_return_type(hints):
    ret = hints.get("return")
    if not ret:
        return "?"
    args = getattr(ret, "__args__", None)
    if args:
        for a in args:
            if "HTTPResponse" not in str(a):
                s = str(a).replace("massive.rest.models.", "").replace("typing.", "")
                return s
    return str(ret).replace("massive.rest.models.", "")


def format_params(sig, hints):
    lines = []
    for pname, p in sig.parameters.items():
        if pname == "self":
            continue
        h = hints.get(pname, "")
        t = str(h).replace("typing.", "").replace("massive.rest.models.common.", "")
        t = t.replace("Union[str, int, datetime.datetime, datetime.date]", "str|int|date")
        t = t.replace("Union[str, int, datetime.datetime, datetime.date, NoneType]", "str|int|date?")
        t = t.replace("<class '", "").replace("'>", "")
        default = "" if p.default is inspect.Parameter.empty else f" = {p.default!r}"
        required = "(required)" if p.default is inspect.Parameter.empty else "(optional)"
        lines.append(f"  {pname}: {t}{default}  {required}")
    return "\n".join(lines)


def cmd_methods():
    methods = get_all_methods()
    from collections import defaultdict
    groups = defaultdict(list)
    for name, (group, attr, hints, sig) in methods.items():
        ret = format_return_type(hints)
        required = [
            pn for pn, p in sig.parameters.items()
            if pn not in ("self", "params", "raw", "options")
            and p.default is inspect.Parameter.empty
        ]
        groups[group].append(f"  {name}({', '.join(required)}) -> {ret}")
    for group in sorted(groups):
        print(f"\n## {group}")
        for line in sorted(groups[group]):
            print(line)


def cmd_method(name):
    methods = get_all_methods()
    if name not in methods:
        # fuzzy match
        matches = [m for m in methods if name.lower() in m.lower()]
        if matches:
            print(f"Method '{name}' not found. Did you mean: {', '.join(matches)}")
        else:
            print(f"Method '{name}' not found.")
        return

    group, attr, hints, sig = methods[name]
    ret = format_return_type(hints)
    print(f"## {name}")
    print(f"Group: {group}")
    print(f"Returns: {ret}")
    print(f"\nParameters:")
    print(format_params(sig, hints))

    # Also show the return model fields
    models = get_all_models()
    # Extract model name from return type
    ret_clean = ret.replace("List[", "").replace("Iterator[", "").rstrip("]")
    ret_clean = ret_clean.replace("<class '", "").replace("'>", "")
    if ret_clean in models:
        print(f"\n## Return model: {ret_clean}")
        for fname, ftype in models[ret_clean].items():
            print(f"  {fname}: {ftype}")


def cmd_model(name):
    models = get_all_models()
    if name in models:
        print(f"## {name}")
        for fname, ftype in models[name].items():
            print(f"  {fname}: {ftype}")
        return

    # fuzzy match
    matches = [m for m in models if name.lower() in m.lower()]
    if len(matches) == 1:
        m = matches[0]
        print(f"## {m}")
        for fname, ftype in models[m].items():
            print(f"  {fname}: {ftype}")
    elif matches:
        print(f"Multiple matches for '{name}':")
        for m in matches:
            fields = models[m]
            print(f"  {m}: {', '.join(list(fields.keys())[:8])}{'...' if len(fields) > 8 else ''}")
    else:
        print(f"Model '{name}' not found.")


def cmd_models():
    models = get_all_models()
    for name, fields in sorted(models.items()):
        print(f"  {name}: {', '.join(list(fields.keys())[:6])}{'...' if len(fields) > 6 else ''}")


def cmd_search(keyword):
    keyword = keyword.lower()
    methods = get_all_methods()
    models = get_all_models()

    found_methods = [n for n in methods if keyword in n.lower()]
    found_models = [n for n in models if keyword in n.lower()]

    if found_methods:
        print("Methods:")
        for name in found_methods:
            _, _, hints, sig = methods[name]
            ret = format_return_type(hints)
            required = [
                pn for pn, p in sig.parameters.items()
                if pn not in ("self", "params", "raw", "options")
                and p.default is inspect.Parameter.empty
            ]
            print(f"  {name}({', '.join(required)}) -> {ret}")

    if found_models:
        print("Models:")
        for name in found_models:
            fields = models[name]
            print(f"  {name}: {', '.join(list(fields.keys())[:8])}{'...' if len(fields) > 8 else ''}")

    if not found_methods and not found_models:
        print(f"No matches for '{keyword}'.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "methods":
        cmd_methods()
    elif cmd == "method" and len(sys.argv) >= 3:
        cmd_method(sys.argv[2])
    elif cmd == "model" and len(sys.argv) >= 3:
        cmd_model(sys.argv[2])
    elif cmd == "models":
        cmd_models()
    elif cmd == "search" and len(sys.argv) >= 3:
        cmd_search(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
