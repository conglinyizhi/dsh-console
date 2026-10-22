// 隔离 home 的两次搬家：isolate_profile（移进自己的 home）与 deisolate_profile（移回共用 home），
// 以及它们用到的回滚（put_back）、回收站落点（move_remainder_to_trash）、凭证路径那条 patch。
//
// 2026-10-20 从 homes.mbt 拆出来：搬家是「动磁盘」的那一半，与 home 归属的读数（homes.mbt）
// 分开读更安全。只搬位置，函数体一个字没改。

///|
/// 一次「移到独立 home」的结果（规格第 9 节：这是真移动，不是复制）。
pub(all) struct IsolateOutcome {
  profile : String
  /// 隔离 home 根：<root>/<名字>
  path : String
  /// 配置目录：<root>/<名字>/profiles/<名字>
  profile_dir : String
  /// 移之前它在哪儿：<DSH_HOME>/profiles/<名字>
  from : String
  /// 同设备那一条的实测（两边设备号），进回执的悬停当证据
  device_note : String
  /// 移动后那三条核对过了（过不了不会走到成功这一支：一律移回原处）
  verified : Bool
  /// 移过来的 node_modules 指向哪儿（没有这一项就是空串）
  node_modules_target : String
  /// skills 软链摆上了吗（源 <DSH_HOME>/skills 不存在时不摆）
  skills_linked : Bool
  /// 凭证路径（写进 cordis.patch.yml 那一条 config.path 的值）
  credentials_path : String
  /// 用的配置键（证据里要说清是哪一个键）
  credentials_key : String
  created_at : String?
  /// 搬家后重算的相对软链接条数（§48.1）
  links_fixed : Int32
  /// 跳过的链接条数：目标找不到（原本就坏），不猜（§48.1）
  links_broken : Int32
  /// cordis.patch.yml / package.json 里换掉的旧目录前缀条数（§48.2）
  refs_rewritten : Int32
}

///|
/// 一次「移回共用 home」的结果。
///
/// 两件事分开报：profile 目录移回到哪儿（to），以及这份额外 home 里**剩下的**东西
/// 移进了回收站哪一条（trash_path）。混成一句会让「我的会话还在不在」这个问题没人答。
pub(all) struct DeisolateOutcome {
  profile : String
  /// 移回到哪儿：<DSH_HOME>/profiles/<名字>
  to : String
  /// 原来那份额外 home（移完就没了）
  home : String
  /// 剩下的东西进了回收站的哪一条：<trash>/homes/<名字>-<毫秒>
  trash_path : String
  /// 怎么移进去的、跳过了什么（人话，进悬停）
  trash_note : String
  /// 移进回收站那一份的文件数与字节数；数不到给 None + 原因
  files : Int32?
  bytes : Int64?
  size_source : String
  /// 搬回来之后重算的相对软链接条数（§48.1）
  links_fixed : Int32
  /// 跳过的链接条数：目标找不到（原本就坏）
  links_broken : Int32
  /// cordis.patch.yml / package.json 里换掉的旧目录前缀条数（§48.2）
  refs_rewritten : Int32
}

///|
/// 移动过关之后又发现不对：把目录移回原处，并把「已经放回原处」这件事写进回执。
///
/// 这一支必须把话说全（规格 9.2 第 5 条）：能放回去与放不回去是两种完全不同的处境，
/// 后者要指名那条路径还在哪儿，不能只报一句「失败」。
async fn put_back(
  home : String,
  src_dir : String,
  profile_dir : String,
  code : String,
  message : String,
) -> Result[IsolateOutcome, (String, String)] noraise {
  let note = match @fsx.rename_path(profile_dir, src_dir) {
    Ok(_) =>
      match @fsx.to_result_unit(@fsx.remove_tree_fs(home)) {
        Ok(_) => "；移动没完成，已经放回原处（" + src_dir + "）"
        Err(e) =>
          "；移动没完成，已经放回原处（" +
          src_dir +
          "），但刚建的 " +
          home +
          " 没能删掉：" +
          e
      }
    Err(e) =>
      "；移动没完成，也没能放回原处：" +
      e +
      "（" +
      profile_dir +
      " 现在还在那儿，要手动挪回 " +
      src_dir +
      "）"
  }
  Err((code, message + note))
}

///|
/// 取消隔离时，「剩下的东西」整份移进回收站：<trash>/homes/<名字>-<毫秒>。
///
/// 口径（规格 9.4 第 2 条）：不复用、不删 —— 会话、插件状态、日志、插件写在根下的目录
/// 一起搬进回收站，事后能捞回来。搬的方式先试 rename（同盘 O(1)）；跨盘 rename 会 EXDEV，
/// 那一支退回复制再删，并把「软链跳过了」写进那句人话（复制只搬普通文件与目录）。
async fn move_remainder_to_trash(
  home : String,
  name : String,
) -> Result[(String, String), String] noraise {
  let root = @store.state_paths().trash
  let bucket = @json.join_path(root, trash_homes_dir)
  match @fsx.ensure_dir_fs(bucket) {
    Ok(_) => ()
    Err(e) => {
      @store.note_raw(e.raw)
      return Err("建目录失败")
    }
  }
  let stamp = @async.now().to_string()
  let dest = @json.join_path(bucket, name + "-" + stamp)
  if @json.exists(dest) {
    return Err(
      "回收站里已经有这一条了：" + dest + "（不覆盖）",
    )
  }
  match @fsx.rename_path(home, dest) {
    Ok(_) =>
      Ok(
        (
          dest, "整份 rename 进回收站（同一文件系统，没复制内容）",
        ),
      )
    Err(first) =>
      match @fsx.copy_tree(home, dest, []) {
        Ok(stats) => {
          let skipped = if stats.skipped.length() > 0 {
            "；跳过了 " + stats.skipped.join("、")
          } else {
            ""
          }
          match @fsx.to_result_unit(@fsx.remove_tree_fs(home)) {
            Ok(_) =>
              Ok(
                (
                  dest,
                  first +
                  "；退回复制再删（" +
                  stats.files.to_string() +
                  " 个文件" +
                  skipped +
                  "）",
                ),
              )
            Err(e) =>
              Err(
                first +
                "；退回复制成功了，但删源头失败：" +
                e +
                "（这份东西在两处各有一份）",
              )
          }
        }
        Err(e) => Err(first + "；退回复制也失败：" + e)
      }
  }
}

///|
/// 往隔离 home 的 cordis.patch.yml 里补一条凭证路径。
///
/// 键的来历：dsh --profile <名字> --dump-config-schema 里
/// credentials（@deepseek-ai/dsh-credentials-local）的 config schema 有 path / dshHome /
/// watch / debounceMs 四项，其中 path 就是凭证文件的位置。所以写：
///
///   - id: credentials
///     config:
///       path: "<DSH_HOME>/.credentials.yaml"
///
/// 源 patch 是空数组占位（只有注释与一个 []）时，那个 [] 要先去掉：
/// 它已经是根节点，后面再接一条 entry 就不是同一个 YAML 文档了（headless 这类 profile 就是这样）。
async fn add_credentials_patch(
  path : String,
  cred_path : String,
) -> Result[Unit, String] noraise {
  let existing = match @json.read_text_file(path) {
    Ok(text) => text
    Err(_) => ""
  }
  let kept : Array[String] = []
  for line in existing.split("\n") {
    let text = @json.trim_both(@json.owned(line))
    if text == "[]" {
      continue
    }
    kept.push(@json.owned(line))
  }
  let mut body = kept.join("\n")
  while body.length() > 0 && body.has_suffix("\n") {
    body = body[:body.length() - 1].to_owned()
  }
  let head = "# 隔离 home 的凭证只给路径：不复制、不软链（软链会被原子写换成明文副本，" +
    "每个 home 里就多一份密钥）。\n" +
    "# 这一条由 dsh-console 的隔离动作写进来；密钥本身留在 " +
    cred_path +
    "。\n"
  let block = "- id: " +
    credentials_entry_id +
    "\n" +
    "  config:\n" +
    "    path: " +
    yaml_quote(cred_path) +
    "\n"
  let text = if body == "" { head + block } else { body + "\n" + head + block }
  @fsx.to_result_unit(@fsx.write_text_atomic_fs(path, text))
}

///|
/// 把一只 profile **移**进它的独立 home（规格第 9 节：真移动，不是复制）。
///
/// 步骤照 9.2 / 9.3：
///   1. 前件：名字是单段、原处是真的 profile 目录、目标不存在（不覆盖）、两边同一个文件系统；
///   2. rename `<DSH_HOME>/profiles/<名字>` → `<root>/<名字>/profiles/<名字>`（同盘 O(1)）；
///   3. 移动后核对三条（profiles/<名字> 在、package.json 读得出、node_modules 有就指得通）；
///   4. 再铺隔离 home 的其余部分：skills 软链、logs/、凭证路径那条 patch、隔离记录。
///
/// 任何一条不过都**移回原处**，并把「已经放回原处」写进回执（9.2 第 5 条）——
/// 不留半成品，也不留一只找不着的 profile。
///
/// 有实例在跑由调用方（actions 的 isolated_home_guard）先挡：这里只管磁盘。
pub async fn isolate_profile(
  name_in : String,
) -> Result[IsolateOutcome, (String, String)] noraise {
  let name = @json.trim_both(name_in)
  if !single_segment(name) {
    return Err(
      (
        "bad-params",
        "profile 名要是单段（不含 / 与 ..，非空）：" + name,
      ),
    )
  }
  let (root, root_source) = homes_root()
  let (dsh_home, _dsh_home_source) = @runtime.resolve_dsh_home()
  let src_dir = @json.join_all([dsh_home, "profiles", name])
  if !@json.is_dir(src_dir) {
    return Err(
      (
        "not-found",
        "profile 目录不存在：" +
        src_dir +
        "（homes root 来自 " +
        root_source +
        "：" +
        root +
        "）",
      ),
    )
  }
  let home = isolated_home_dir(root, name)
  // 硬约束：目标必须正好是 <root>/<单段名字>，拼出来不是这一条就不动
  if home != root + "/" + name {
    return Err(
      ("bad-params", "隔离 home 路径不在 " + root + " 下：" + home),
    )
  }
  if @json.exists(home) {
    return Err(
      (
        "conflict",
        "隔离 home 已经存在：" +
        home +
        "（不覆盖；要重建先移回共用 home）",
      ),
    )
  }
  let src_parent = @json.join_all([dsh_home, "profiles"])
  let dst_parent = @json.join_all([home, "profiles"])
  match @fsx.ensure_dir_fs(dst_parent) {
    Ok(_) => ()
    Err(e) => {
      @store.note_raw(e.raw)
      return Err(("io-error", "建目录失败"))
    }
  }
  // 落点目录已经建了：从这里往后任何一条不过，都要把 <root>/<名字> 收掉再报
  let device_note = match require_same_device(src_parent, dst_parent) {
    Err((code, message)) => {
      let _ = @fsx.to_result_unit(@fsx.remove_tree_fs(home))
      return Err(
        (
          code,
          message +
          "；刚建的 " +
          home +
          " 已经删掉，" +
          src_dir +
          " 一个字都没动",
        ),
      )
    }
    Ok(note) => note
  }
  let profile_dir = @json.join_all([home, "profiles", name])
  match move_dir(src_dir, profile_dir) {
    Err((code, message)) => {
      let _ = @fsx.to_result_unit(@fsx.remove_tree_fs(home))
      return Err(
        (
          code,
          message +
          "；刚建的 " +
          home +
          " 已经删掉，" +
          src_dir +
          " 一个字都没动",
        ),
      )
    }
    Ok(_) => ()
  }
  // 搬家之后先重算相对软链接（§48.1）：多两层深度，同一段 ../../ 会指到别处。
  // 必须在核对之前做 —— 坏链接会让 node_modules 那一项核对不过，然后一路回滚。
  let relink = relink_after_move(src_dir, profile_dir)
  // 移动之后那三条核对（9.2 第 4 条）。移过来的 node_modules 是这一份自己带着的，
  // 所以只核对「指得通」，不比对目标。
  match verify_isolated(profile_dir, "") {
    Some(problem) =>
      return put_back(
        home,
        src_dir,
        profile_dir,
        "io-error",
        "移动之后的核对没过：" + problem,
      )
    None => ()
  }
  // 铺其余部分：skills 软链（源里有才摆）、logs/、凭证路径那条 patch、隔离记录
  let mut skills_linked = false
  let src_skills = @json.join_path(dsh_home, "skills")
  if @json.is_dir(src_skills) {
    match @fsx.to_result_unit(@fsx.make_symlink_fs(src_skills, @json.join_path(home, "skills"))) {
      Ok(_) => skills_linked = true
      Err(e) =>
        return put_back(
          home,
          src_dir,
          profile_dir,
          "io-error",
          "摆 skills 软链失败：" + e,
        )
    }
  }
  match @fsx.to_result_unit(@fsx.ensure_dir_fs(@json.join_path(home, "logs"))) {
    Ok(_) => ()
    Err(e) =>
      return put_back(
        home,
        src_dir,
        profile_dir,
        "io-error",
        "建 logs/ 失败：" + e,
      )
  }
  // 凭证：只写路径，不碰文件本身（@json.exists 只 stat，不读内容）
  let cred = @json.join_path(dsh_home, ".credentials.yaml")
  match
    add_credentials_patch(
      @json.join_path(profile_dir, "cordis.patch.yml"),
      cred,
    ) {
    Ok(_) => ()
    Err(e) =>
      return put_back(
        home,
        src_dir,
        profile_dir,
        "io-error",
        "写凭证路径失败：" + e,
      )
  }
  let created = @json.iso_from_epoch_ms(@async.now())
  let marker = @json.JObj([
    ("profile", @json.JStr(name)),
    ("createdAt", @json.JStr(created)),
    ("kind", @json.JStr(home_kind_isolated)),
    ("dshHome", @json.JStr(dsh_home)),
    ("homesRoot", @json.JStr(root)),
    ("movedFrom", @json.JStr(src_dir)),
    ("deviceNote", @json.JStr(device_note)),
    ("credentialsPath", @json.JStr(cred)),
    ("credentialsKey", @json.JStr("credentials.config.path")),
  ])
  match
    @fsx.to_result_unit(@fsx.write_text_atomic_fs(
      @json.join_path(home, isolation_marker),
      @json.encode(marker) + "\n",
    )) {
    Ok(_) => ()
    Err(e) =>
      return put_back(
        home,
        src_dir,
        profile_dir,
        "io-error",
        "写隔离记录失败：" + e,
      )
  }
  Ok({
    profile: name,
    path: home,
    profile_dir,
    from: src_dir,
    device_note,
    verified: true,
    node_modules_target: node_modules_target_of(profile_dir),
    skills_linked,
    credentials_path: cred,
    credentials_key: "credentials.config.path",
    created_at: Some(created),
    links_fixed: relink.links_fixed,
    links_broken: relink.links_broken,
    refs_rewritten: relink.refs_rewritten,
  })
}

///|
/// 把一只 profile **移回**共用 home（规格 9.4）。
///
/// 两步，两步都要如实报：
///   1. `<root>/<名字>/profiles/<名字>` → `<DSH_HOME>/profiles/<名字>`，同一套前件与校验
///      （同设备、目标不存在、移动后核对），任何一条不过就移回原处并报「移动没完成，已经放回原处」；
///   2. 这份额外 home 里**剩下的**东西（sessions、storages、logs、插件写在根下的目录）
///      不移回、也不删：整份移进回收站 `<trash>/homes/<名字>-<毫秒>/`，事后能捞回来。
///
/// 硬约束：只碰 `<root>/<单段名字>` 与 `<DSH_HOME>/profiles/<单段名字>` 这两条路径，
/// 两边都用拼出来的值核对过；不接收客户端给的任何路径。
///
/// 有实例在跑由调用方（actions 的 isolated_home_guard）先挡：这里只管磁盘。
pub async fn deisolate_profile(
  name_in : String,
) -> Result[DeisolateOutcome, (String, String)] noraise {
  let name = @json.trim_both(name_in)
  if !single_segment(name) {
    return Err(
      (
        "bad-params",
        "profile 名要是单段（不含 / 与 ..，非空）：" + name,
      ),
    )
  }
  let (root, root_source) = homes_root()
  let (dsh_home, _dsh_home_source) = @runtime.resolve_dsh_home()
  let home = isolated_home_dir(root, name)
  if home != root + "/" + name {
    return Err(
      ("bad-params", "隔离 home 路径不在 " + root + " 下：" + home),
    )
  }
  if !@json.is_dir(home) {
    return Err(
      (
        "not-found",
        "没有隔离 home：" +
        home +
        "（homes root 来自 " +
        root_source +
        "）",
      ),
    )
  }
  let src_dir = @json.join_all([home, "profiles", name])
  if !@json.is_dir(src_dir) {
    return Err(
      (
        "not-found",
        "这份 home 里没有 profiles/" +
        name +
        "：" +
        src_dir +
        "（读数说它是隔离的，磁盘上不在）",
      ),
    )
  }
  let dst_parent = @json.join_all([dsh_home, "profiles"])
  let dst = @json.join_path(dst_parent, name)
  if @json.exists(dst) {
    return Err(
      (
        "conflict",
        "共用 home 里已经有同名 profile：" +
        dst +
        "（不覆盖；先给它改名或删掉，再移回）",
      ),
    )
  }
  match @fsx.ensure_dir_fs(dst_parent) {
    Ok(_) => ()
    Err(e) => {
      @store.note_raw(e.raw)
      return Err(("io-error", "建目录失败"))
    }
  }
  let src_parent = @json.join_all([home, "profiles"])
  match require_same_device(src_parent, dst_parent) {
    Err((code, message)) =>
      return Err((code, message + "；" + src_dir + " 还在原处"))
    Ok(_) => ()
  }
  match move_dir(src_dir, dst) {
    Err((code, message)) =>
      return Err((code, message + "；" + src_dir + " 还在原处"))
    Ok(_) => ()
  }
  // 搬回来也要重算（方向反了，深度变了同样会断，§48.1）
  let relink = relink_after_move(src_dir, dst)
  match verify_isolated(dst, "") {
    Some(problem) => {
      let note = match @fsx.rename_path(dst, src_dir) {
        Ok(_) => "；移动没完成，已经放回原处（" + src_dir + "）"
        Err(e) =>
          "；移动没完成，也没能放回原处：" +
          e +
          "（" +
          dst +
          " 现在在共用 home 里，要手动挪回 " +
          src_dir +
          "）"
      }
      return Err(
        ("io-error", "移动之后的核对没过：" + problem + note),
      )
    }
    None => ()
  }
  // 剩下的东西：整份移进回收站，不删。
  let (files, bytes, size_source) = match @fsx.measure_tree(home) {
    Ok((f, b)) => (Some(f), Some(b), "")
    Err(e) => (None, None, e)
  }
  match move_remainder_to_trash(home, name) {
    Err(why) =>
      return Err(
        (
          "io-error",
          name +
          " 的目录已经移回共用 home（" +
          dst +
          "），但这份额外 home 里剩下的东西" +
          "没能移进回收站：" +
          why,
        ),
      )
    Ok((trash_path, trash_note)) =>
      Ok({
        profile: name,
        to: dst,
        home,
        trash_path,
        trash_note,
        files,
        bytes,
        size_source,
        links_fixed: relink.links_fixed,
        links_broken: relink.links_broken,
        refs_rewritten: relink.refs_rewritten,
      })
  }
}

// ── 试跑用的一次性 home（design/deep-home-isolation.md 第 6 节、§9.4）────────
//
// 试跑不再借用户真实 home 里的那份 profile：这一份是临时铺出来的，
// 铺法照第 2 节（复制配置、软链 node_modules 与 skills、凭证只写路径），
// 收尾（verdict 的 good / bad、trial-stop、abort）时整份删掉。
//
// 硬约束：只建 / 只删 <homes root>/trial-<作业 id 末 6 位>；
// 删之前按前缀与路径核对，不接收客户端给的任意路径。
