"""Shared Python code for IRIS imaging workflows.

Job scripts put lib/ on PYTHONPATH, so workflows import `iris.volume` and
`iris.labels`. Its packages come from the imaging environment's lock.
"""
