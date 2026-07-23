import { signOut } from "@/lib/auth/actions";

export function WorkspaceHeader({ roleKeys }: { roleKeys: string[] }) {
  return (
    <div className="noor-workspace-header">
      <span className="noor-badge">{roleKeys.join(", ") || "member"}</span>
      <form action={signOut}>
        <button type="submit" className="noor-link-button">
          Sign out
        </button>
      </form>
    </div>
  );
}
