-- Opcional, depois da instalacao: atribuir o primeiro papel global de plataforma.
-- Crie primeiro a SUA conta em Authentication > Users (com senha propria e e-mail confirmado).
-- Copie o UUID dessa conta e substitua somente o UUID abaixo. Nao use dados de outra pessoa.
-- Execute como postgres no SQL Editor. Nao use este arquivo para convites comuns.
begin;
do $bootstrap$
declare target_user uuid := '00000000-0000-0000-0000-000000000000';
begin
  if target_user='00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'Substitua o UUID pelo ID da sua conta confirmada em Authentication > Users.';
  end if;
  if not exists(select 1 from auth.users where id=target_user and email_confirmed_at is not null) then
    raise exception 'Usuario nao encontrado ou e-mail ainda nao confirmado.';
  end if;
  insert into private.platform_roles(user_id,role) values(target_user,'supreme') on conflict do nothing;
end
$bootstrap$;
commit;
select 'Papel supreme atribuido. Entre no app com o e-mail e a senha da conta escolhida.' as resultado;
