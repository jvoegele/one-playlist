import type { NextRequest } from "next/server";
import { updateSession } from "./lib/supabase/proxy";

// This is the Next.js convention for a project-root file that intercepts
// every matched request ahead of Server Components/Route Handlers — the
// mechanism formerly (and in most existing docs/tutorials) called
// "middleware". All the actual logic lives in ./lib/supabase/proxy.ts.
export async function proxy(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    // Match everything except Next's static assets, image optimizer
    // output, favicon.ico, and common static image extensions.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
