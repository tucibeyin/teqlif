"use client";

import { useState } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";

interface DashboardSectionProps {
    title: string;
    id: string;
    count?: number;
    children: React.ReactNode;
    defaultExpanded?: boolean;
}

export default function DashboardSection({
    title,
    id,
    count,
    children,
    defaultExpanded = false,
}: DashboardSectionProps) {
    const [isExpanded, setIsExpanded] = useState(defaultExpanded);

    return (
        <section className="section" id={id} style={{ padding: "1.5rem 0" }}>
            <button
                onClick={() => setIsExpanded(!isExpanded)}
                style={{
                    width: "100%",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    background: "var(--bg-secondary)",
                    border: "1px solid var(--border)",
                    padding: "1rem 1.5rem",
                    borderRadius: "var(--radius-lg)",
                    cursor: "pointer",
                    transition: "var(--transition)",
                    textAlign: "left",
                    boxShadow: "var(--shadow-sm)",
                }}
                className="accordion-trigger"
            >
                <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                    <h2
                        className="section-title"
                        style={{ margin: 0, fontSize: "1.125rem" }}
                    >
                        {title}
                    </h2>
                    {count !== undefined && (
                        <span
                            style={{
                                background: "var(--primary-50)",
                                color: "var(--primary-dark)",
                                padding: "0.125rem 0.625rem",
                                borderRadius: "var(--radius-full)",
                                fontSize: "0.75rem",
                                fontWeight: 700,
                            }}
                        >
                            {count}
                        </span>
                    )}
                </div>
                {isExpanded ? (
                    <ChevronUp size={20} className="text-muted" />
                ) : (
                    <ChevronDown size={20} className="text-muted" />
                )}
            </button>

            {isExpanded && (
                <div
                    style={{
                        marginTop: "1rem",
                        animation: "slideDown 0.2s ease-out",
                    }}
                >
                    <div
                        className="scrollable-list"
                        style={{
                            maxHeight: "600px",
                            overflowY: "auto",
                            paddingRight: "0.5rem",
                        }}
                    >
                        {children}
                    </div>
                </div>
            )}

            <style jsx>{`
        @keyframes slideDown {
          from {
            opacity: 0;
            transform: translateY(-10px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
        .accordion-trigger:hover {
          border-color: var(--primary);
          background: var(--primary-50);
        }
      `}</style>
        </section>
    );
}
