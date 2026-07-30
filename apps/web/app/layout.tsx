import type { Metadata } from "next";
import { Inter, IBM_Plex_Sans_Arabic } from "next/font/google";
import { TokensStyleTag } from "@noor/ui";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--noor-font-latin",
  display: "swap",
});

const plexArabic = IBM_Plex_Sans_Arabic({
  subsets: ["arabic"],
  weight: ["400", "500", "600", "700"],
  variable: "--noor-font-arabic",
  display: "swap",
});

// Read directly, not via getPublicEnv() — that validator requires
// Supabase env vars and would break the static routes (/, /403,
// /access-denied, /design-system) that deliberately build without them.
// metadataBase is cosmetic (resolves relative OG image URLs); a plain
// localhost fallback is safe here.
const metadataBase = new URL(process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000");

export const metadata: Metadata = {
  metadataBase,
  title: "Noor — Clinical Intelligence OS",
  description:
    "Evidence-grounded clinical decision support for healthcare organizations.",
  icons: {
    icon: [
      { url: "/brand/favicon.ico", sizes: "any" },
      { url: "/brand/noor-symbol-32.png", type: "image/png", sizes: "32x32" },
    ],
    apple: [{ url: "/brand/noor-symbol-180.png", sizes: "180x180" }],
  },
  openGraph: {
    title: "Noor — Clinical Intelligence OS",
    description: "Evidence-grounded clinical decision support for healthcare organizations.",
    images: [{ url: "/brand/social-preview.png", width: 1200, height: 630, alt: "Noor — Clinical Intelligence" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Noor — Clinical Intelligence OS",
    images: ["/brand/social-preview.png"],
  },
};

export const viewport = {
  themeColor: "#045092",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" dir="ltr" className={`${inter.variable} ${plexArabic.variable}`}>
      <body className="font-sans antialiased">
        <TokensStyleTag />
        {children}
      </body>
    </html>
  );
}
