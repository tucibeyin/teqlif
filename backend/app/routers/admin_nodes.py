"""
Cluster node metrikleri — admin API.

GET /api/admin/nodes         → tüm aktif node'ların canlı metrikleri
GET /api/admin/nodes/{id}    → tek node detayı
"""

from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException

from app.routers.admin_data import check_admin_access
from app.services.edge_orchestrator import orchestrator

router = APIRouter(prefix="/api/admin/nodes", tags=["admin-nodes"])


@router.get("", dependencies=[Depends(check_admin_access)])
async def list_nodes() -> List[Dict[str, Any]]:
    """Cluster'daki tüm aktif node'ların anlık metriklerini döner."""
    return await orchestrator.get_all_metrics()


@router.get("/{node_id}", dependencies=[Depends(check_admin_access)])
async def get_node(node_id: str) -> Dict[str, Any]:
    """Belirtilen node'un anlık metriklerini döner."""
    for m in await orchestrator.get_all_metrics():
        if m.get("node_id") == node_id:
            return m
    raise HTTPException(status_code=404, detail=f"Node '{node_id}' aktif değil")
