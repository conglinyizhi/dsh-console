// 版本切换（回退）：指定「用哪一版 dsh 起实例」，以及撤销这个指定。
//
// 只改 $XDG_STATE_HOME/dsh-console/dsh-pin.json（见 store/dshpin.mbt）：
// **不碰系统上的 dsh 命令、不碰 pnpm 全局安装**。起实例时的 argv 是
// <包目录>/lib/bin.js，换版本只要换这个包目录 —— 所以使用者回退到旧版不需要动 PATH，
// 也不需要重装任何东西，而且控制台自己跑的还是它自己那份后端。
//
// 为什么「只能在候选里挑」：候选就是这台机器上真装着的 dsh（PATH 上 shim 解开的那份 +
// 各全局根扫到的全部）。允许指定任意目录，等于允许把一个来路不明的目录写进实例的 argv，
// 而那份目录里的 lib/bin.js 是会被直接执行的。这里不顺带做「目录存在就收」。
//
// 指定那一刻把版本号一起记下：目录没变、里面被换成另一个版本时，runtime 那一侧会比出来
// （版本对不上就按 pin-missing 回落并说清），不会拿新版冒充用户指定的旧版。

///|
/// 这个动作收哪些参数：多一个键就拒，免得有人塞个别的键还以为它生效了。
///
/// 不复用 open_path.mbt 里的 ensure_only_keys：那条的报错里写死了「目标只由 profile 与 kind
/// 决定」，用在这里会报出一句与本动作无关的话。
fn ensure_action_params(
  params : Json,
  label : String,
  allowed : Array[String],
) -> Unit raise ActionError {
  match params {
    Object(fields) =>
      for key, _ in fields {
        if !allowed.contains(key) {
          fail(
            "bad-params",
            label +
            (if allowed.length() == 0 {
              "不收参数，收到了 " + key
            } else {
              "只认参数 " + allowed.join("、") + "，收到了 " + key
            }),
          )
        }
      }
    _ => ()
  }
}

///|
/// 一次指定的结果。
pub struct PinOutcome {
  dir : String
  version : String
  pin_path : String
}

///|
/// 一次撤销的结果。
pub struct UnpinOutcome {
  /// 这一趟到底删没删（文件本来就不在时是 false —— 目标状态已经成立，但不是「刚删掉」）
  removed : Bool
  /// 撤之前指定的是哪一版（没有指定给空串）
  previous_version : String
  pin_path : String
}

///|
/// 一个目录的真实路径（读不出来给原串）。
/// 候选里同一份 dsh 有两种写法（pnpm 摆出来的软链 / .pnpm 下的真身），
/// 用户从读数里拿到哪一条都该认成同一份。
async fn real_dir_of(path : String) -> String noraise {
  match @json.real_path(path) {
    Some(p) => p
    None => path
  }
}

///|
/// 指定用哪一版起实例。目录必须在这台机器上真装着的那几份里。
pub async fn pin_dsh(dir_in : String) -> PinOutcome raise ActionError {
  let want = @json.trim_both(dir_in)
  let candidates = @runtime.installed_dsh_candidates()
  let wanted_real = real_dir_of(want)
  let mut picked : @runtime.DshPackage? = None
  for c in candidates {
    if c.dir == want || real_dir_of(c.dir) == wanted_real {
      picked = Some(c)
    }
  }
  let pkg = match picked {
    Some(p) => p
    None => {
      // 说清这台机器上到底装着哪几份：只说「不是装了的一份」而没有清单，用户没法自己纠正
      let installed = if candidates.length() == 0 {
        "一份都没找着"
      } else {
        candidates.map(fn(c) { c.version }).join("、")
      }
      fail(
        "dsh-not-installed",
        "这个目录不是这台机器上装了的一份 dsh：" +
        want +
        "；这台机器上装着：" +
        installed,
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let paths = @store.state_paths()
  let pin : @store.DshPin = {
    dir: pkg.dir,
    version: pkg.version,
    pinned_at: @json.iso_from_epoch_ms(@async.now()),
  }
  match @store.save_dsh_pin(pin) {
    Ok(_) => ()
    Err(e) => {
      fail("io-error", "指定没能写进 " + paths.dsh_pin + "：" + e)
      abort("unreachable: fail 一定抛错")
    }
  }
  { dir: pkg.dir, version: pkg.version, pin_path: paths.dsh_pin, }
}

///|
/// 撤掉指定，回到自动挑。
/// 文件本来就不存在也算成功（目标状态已经成立），但 removed 如实说这一趟到底删没删 ——
/// 界面不该把「本来就没有」说成「刚删掉」。
pub async fn unpin_dsh() -> UnpinOutcome raise ActionError {
  let paths = @store.state_paths()
  let previous = match @store.load_dsh_pin() {
    Some(p) => p.version
    None => ""
  }
  let removed = @json.exists(paths.dsh_pin)
  match @store.clear_dsh_pin() {
    Ok(_) => ()
    Err(e) => {
      fail("io-error", "指定没能删掉 " + paths.dsh_pin + "：" + e)
      abort("unreachable: fail 一定抛错")
    }
  }
  { removed, previous_version: previous, pin_path: paths.dsh_pin, }
}
