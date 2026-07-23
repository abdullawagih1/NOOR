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

export const metadata: Metadata = {
  title: "Noor — Clinical Intelligence OS",
  description:
    "Evidence-grounded clinical decision support. Sprint 0.5 design-system foundation.",
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
