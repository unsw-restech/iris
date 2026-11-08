"""Shared Python code for IRIS imaging workflows.

Job scripts put this package's folder on PYTHONPATH, so workflows import
`iris.volume` and `iris.labels`. A job imports its workflow's own copy of
the job side (bin/libcopy, workflows/<slug>/lib/); the shared side, the
importer, iris-view and iris-compare, runs from the clone's lib/. Its
packages come from the environment's lock.
"""
