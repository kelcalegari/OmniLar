-- 0071: e-mail do perfil acompanha o e-mail de acesso
--
-- profiles.email é o que os outros moradores veem. Até aqui ele só era
-- gravado no cadastro (handle_new_user, 0068); depois de uma troca de e-mail
-- confirmada (pelo app ou pelo link do e-mail) ele ficava com o endereço
-- antigo. Este gatilho copia o novo e-mail sempre que auth.users.email muda,
-- e uma correção única alinha quem já está diferente.

create or replace function public.sync_profile_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set email = new.email,
         updated_at = now()
   where id = new.id
     and email is distinct from new.email;
  return new;
end;
$$;

revoke all on function public.sync_profile_email() from public, anon, authenticated;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (old.email is distinct from new.email)
  execute function public.sync_profile_email();

-- Correção única: perfis com e-mail vazio ou desatualizado
update public.profiles p
   set email = u.email,
       updated_at = now()
  from auth.users u
 where u.id = p.id
   and u.email is not null
   and p.email is distinct from u.email;
