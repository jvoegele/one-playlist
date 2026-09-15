import { Button } from "@/components/ui/button";
import { login } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4">
      {error && <p className="text-destructive text-sm">{error}</p>}

      <form action={login} className="flex flex-col gap-2">
        <label htmlFor="email">Email</label>
        <input name="email" type="email" />

        <label htmlFor="password">Password</label>
        <input name="password" type="password" />

        <Button type="submit">Log in</Button>
      </form>
    </div>
  );
}
