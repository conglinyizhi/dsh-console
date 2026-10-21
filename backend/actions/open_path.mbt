// 打开目录 / 打开配置：POST /api/local/action 的 open-path 动作（第三轮契约第一节）。
//
// 这个动作**不接受客户端给的路径**：参数只有 profile 名与一个枚举 kind，目标由后端自己拼 ——
//   kind = "dir"（缺省）  -> <profilesRoot>/<名>
//   kind = "config"      -> <profilesRoot>/<名>/cordis.patch.yml
// 名字先过白名单，拼出来的路径再确认落在 profilesRoot 之内（两道，与 set-profile-note 同款）。
// params 里出现 profile / kind 之外的键一律拒 —— 免得有人塞个 path 还以为它生效了。
//
// 交给桌面环境用 xdg-open **直接 exec**：不经 shell、不做字符串插值（目标路径是 argv 里的一项，
// 就算带空格、引号、$ 也只是这一项的字面量），spawn 之后不等它干活。
//
// 打不开的情形如实报 io-error，三种各说各的，不假装成功：
//   · PATH 里没有 xdg-open；
//   · 没有图形环境（DISPLAY 与 WAYLAND_DISPLAY 都没设）；
//   · xdg-open 起来就立刻非零退出（把退出码与它 stderr 的尾部一并给出来）。

///|
/// 用的 opener。固定 xdg-open：这一层只做「交给桌面环境」，不替使用者挑程序。
pub let open_program : String = "xdg-open"

///|
/// profile 的配置文件（kind = "config" 的目标）。与 profiles 只读那边读的是同一个文件。
pub let config_file_name : String = "cordis.patch.yml"

///|
/// spawn 之后看它是不是立刻就挂了的时间窗。
/// 这不是「等它干活」：xdg-open 打不开时是毫秒级退出，打得开时要么把活交出去自己退出（0），
/// 要么留着跑。这个窗口只用来分辨这几种情况。
let open_probe_ms : Int32 = 600

///|
/// 一次打开的结果。
pub struct OpenPathOutcome {
  /// "dir" 或 "config"
  what : String
  /// 解析出来的绝对路径（枚举目标算出来的，不是客户端给的）
  path : String
  /// 实际用的 opener 绝对路径
  opener : String
  /// xdg-open 的 pid
  pid : Int32
  /// 探测窗内就退出时它的退出码；还在跑给 None
  exit_code : Int32?
  /// 探测窗内退出时它 stderr 的尾部（掏空给空串）
  detail : String
}

///|
/// params 里只许出现这些键。多一个就拒（open-path 没有路径参数这回事）。
fn ensure_only_keys(
  params : Json,
  allowed : Array[String],
) -> Unit raise ActionError {
  match params {
    Object(fields) =>
      for key, _ in fields {
        if !allowed.contains(key) {
          fail(
            "bad-params",
            "open-path 不接受参数 " +
            key +
            "：目标只由 profile 与 kind 决定，没有路径参数",
          )
        }
      }
    _ => ()
  }
}

///|
/// 取文本的最后 n 个非空行（贴进失败信息用）。
fn tail_lines(text : String, lines : Int32) -> String {
  let kept : Array[String] = []
  for line in text.split("\n") {
    let trimmed = @json.trim_both(@json.owned(line))
    if trimmed != "" {
      kept.push(trimmed)
    }
  }
  let start = if kept.length() > lines { kept.length() - lines } else { 0 }
  kept[start:].to_owned().join(" / ")
}

///|
/// 执行一次 open-path。目标不存在 -> not-found；打不开 -> io-error。
pub async fn open_path(
  profile : String,
  kind : String?,
) -> OpenPathOutcome raise ActionError {
  let name = @json.trim_both(profile)
  validate_profile_name(name)
  // 「工作目录 / 配置」指的是这只 profile **自己现在那一份**：隔离的那一只在它的 home 里。
  let (dir, home) = @profiles.profile_location(name)
  let root = @json.join_path(home, "profiles")
  // 防目录穿越的第二道：白名单已经保证 name 是单段（无斜杠、不是 . / ..），
  // 这里再确认拼出来的路径确实在 profilesRoot 里面，两道都留着。
  if !dir.has_prefix(root + "/") || dir == root {
    fail("bad-params", "profile 名解析到了 profilesRoot 之外：" + dir)
  }
  let wanted = match kind {
    Some(k) => @json.trim_both(k)
    None => "dir"
  }
  let (what, path) = match wanted {
    "dir" => ("dir", dir)
    "config" => ("config", @json.join_path(dir, config_file_name))
    _ => {
      fail("bad-params", "kind 只接受 dir 与 config，收到：" + wanted)
      abort("unreachable: fail 一定抛错")
    }
  }
  if !path.has_prefix(root + "/") {
    fail("bad-params", "目标解析到了 profilesRoot 之外：" + path)
  }
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  if what == "config" && !@json.exists(path) {
    fail(
      "not-found",
      "profile " + name + " 没有 " + config_file_name + "：" + path,
    )
  }
  let opener = match find_in_path(open_program) {
    Some(p) => p
    None => {
      fail(
        "io-error",
        "PATH 里找不到 " +
        open_program +
        "（这台机器上没装 xdg-utils），打不开 " +
        path,
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  // 没有图形环境时 xdg-open 必定打不开。先如实报出来，不交给它去失败。
  let on_x = match @json.env_value("DISPLAY") {
    Some(_) => true
    None => false
  }
  let on_wayland = match @json.env_value("WAYLAND_DISPLAY") {
    Some(_) => true
    None => false
  }
  if !on_x && !on_wayland {
    fail(
      "io-error",
      "没有图形环境：DISPLAY 与 WAYLAND_DISPLAY 都没设置，xdg-open 打不开 " +
      path +
      "（控制台要把窗口交出去，得有个桌面会话接着）",
    )
  }
  let state = @store.state_paths()
  let _ = @fsx.ensure_dir(state.dir)
  let capture = @json.join_path(
    state.dir,
    "open-path-" + @async.now().to_string() + ".log",
  )
  // 它的话（stderr）落到状态目录下一个一次性文件里：探测窗过了就读出来、随即删掉。
  // 建不了这个文件就退回 /dev/null —— 记不下它说的话，不该让「打开目录」直接失败。
  let mut captured = true
  let out = @process.redirect_to_file(
    capture,
    create_mode=OpenOrCreate,
    permission=0o600,
  ) catch {
    _ => {
      captured = false
      @process.redirect_to_file(
        "/dev/null",
        create_mode=OpenOrCreate,
        permission=0o600,
      ) catch {
        err => {
          fail("io-error", "打不开 /dev/null：" + err.to_string())
          abort("unreachable: fail 一定抛错")
        }
      }
    }
  }
  let input = @process.redirect_from_file("/dev/null") catch {
    err => {
      fail("io-error", "打不开 /dev/null：" + err.to_string())
      abort("unreachable: fail 一定抛错")
    }
  }
  // argv 就是 opener 与目标两项，没有 shell、没有拼串：目标里有什么字符都只是这一项的字面量
  let pid = @process.spawn_orphan(
    opener,
    [path],
    stdin=input,
    stdout=out,
    stderr=out,
  ) catch {
    err => {
      let _ = @fsx.remove_file(capture)
      fail("io-error", "起 " + opener + " 失败：" + err.to_string())
      abort("unreachable: fail 一定抛错")
    }
  }
  out.close()
  let began = @async.now()
  while (@async.now() - began).to_int() < open_probe_ms {
    if !process_alive(pid) {
      break
    }
    @async.sleep(50)
  }
  let mut exit_code : Int32? = None
  if !process_alive(pid) {
    exit_code = Some(@process.wait_pid(pid)) catch { _ => None }
  } else {
    // 它活得比探测窗长，这会儿还收不了。挂一只后台协程等它退出 ——
    // 不然后来它退出时没人 wait，会在控制台名下留一只僵尸（detach 实例那条路同理）。
    spawn_reaper(async fn() {
      try {
        let _ = @process.wait_pid(pid)
      } catch {
        _ => ()
      }
      ()
    })
  }
  let detail = if captured {
    let text = match @json.read_text_file(capture) {
      Ok(t) => t
      Err(_) => ""
    }
    let _ = @fsx.remove_file(capture)
    tail_lines(text, 3)
  } else {
    ""
  }
  match exit_code {
    Some(code) =>
      if code != 0 {
        fail(
          "io-error",
          opener +
          " 起来就退出了（退出码 " +
          code.to_string() +
          "），" +
          path +
          " 没打开" +
          (if detail == "" {
            "；它没有输出"
          } else {
            "；它说：" + detail
          }),
        )
      }
    None => ()
  }
  { what, path, opener, pid, exit_code, detail, }
}
