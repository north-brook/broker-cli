"""Backward-compatible re-export of provider interfaces."""

from broker_daemon.providers.base import ConnectionStatus
from broker_daemon.providers.ib import IBProvider

IBConnectionManager = IBProvider

__all__ = ["ConnectionStatus", "IBConnectionManager"]
