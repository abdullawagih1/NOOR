"use client";

import { Component, type ReactNode } from "react";

interface CanvasErrorBoundaryProps {
  children: ReactNode;
  fallback: ReactNode;
}

interface CanvasErrorBoundaryState {
  hasError: boolean;
}

/**
 * Catches Three.js/R3F initialization or shader-compile failures
 * (mission §43) and falls back to the static experience automatically
 * — never a blank canvas, never a raw stack trace shown to the user.
 */
export class CanvasErrorBoundary extends Component<CanvasErrorBoundaryProps, CanvasErrorBoundaryState> {
  state: CanvasErrorBoundaryState = { hasError: false };

  static getDerivedStateFromError(): CanvasErrorBoundaryState {
    return { hasError: true };
  }

  componentDidCatch(error: Error): void {
    if (process.env.NODE_ENV !== "production") {
      // Safe development diagnostic only — never a raw stack trace in production.
      console.warn("[cinematic-landing] canvas error, falling back to static experience:", error.name);
    }
  }

  render() {
    if (this.state.hasError) return this.props.fallback;
    return this.props.children;
  }
}
