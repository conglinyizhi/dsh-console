// GET /api/local/console —— 控制台自己的运行时读数（只读）。
//
// 为什么要有这个端点：runtime.json（哪些实例是本控制台起的）、archive.json（归档记录）
// 与 order.json（手动排序的顺序表）是三份状态文件，前端拿不到文件系统。契约里那五个
// 只读接口的形状一个字段都不许动，所以这里另开一个只读端点把它们如实读出去；
// 它本身不写任何东西（alive 是读 /proc 判的）。
//
// 第十轮这里多了两项读数：
//   order        手动排序的显式顺序表（行 id 的数组）。空数组 = 没拖过 = 走自动排序。
//   lastStarted  每只实例 / profile 最后一次被启动的时刻，卡片第二行的第三顺位用它
//                （有备注写备注，没备注才写它，两个都没有就空着）。

///|
/// 生效的删除方式与它的来源（文件 / 默认）。
///
/// 为什么在这里出一份：设置是**懒加载**的（设置页打开过才读 GET /api/local/settings），
/// 而删除确认框在打开之前就得说清「删了会怎样」。这个端点是「控制台自身状态」的出口，
/// 页面加载时本来就会读，把生效值摆在这儿，前端不必先读过设置也能知道。
///
/// 值取自 @store.load_settings()，与删除动作（actions/profile_fs.mbt）用的是同一处 ——
/// 两处各算一遍迟早会分叉，分叉出来就是「确认框说进回收站、动作却硬删」。
async fn delete_mode_fields() -> Array[(String, @json.JsonVal)] noraise {
  let loaded = @store.load_settings()
  let source = match loaded.sources.get(@store.key_safety_delete_to_trash) {
    Some(s) => s
    None => "默认"
  }
  [
    ("deleteToTrash", @json.JBool(loaded.values.safety_delete_to_trash)),
    ("deleteToTrashSource", @json.JStr(source)),
  ]
}

///|
/// 控制台状态响应。
async fn console_payload() -> @json.JsonVal noraise {
  let paths = @store.state_paths()
  let registry = @store.load_registry()
  let archive = @store.load_archive()
  // 构建信息（scripts/gen-build-info.sh 生成）：页脚要显示服务端这一份 sha
  let build_sha = @store.build_sha
  let build_at = @store.build_at
  let order = @store.load_order()
  let (last_started, last_started_notes) = @store.load_last_started()
  // 维护作业（design/ops-maintenance-jobs.md §2 / §3）：读不出来的那条也一起交出去，
  // 不吞 —— 那条记录必须在列表里显示「记录读不出来」+ 原因。
  let (jobs, bad_jobs, job_notes) = @store.load_jobs()
  // P1 对账（批注 3）：**以 /proc 里的真实进程为准**，runtime.json 只补元数据。
  // 以前这里是「遍历注册表 → alive = process_alive(pid)」，与 instances 读数是两套判定；
  // 现在统一走 instances 报告（它已经做过 /proc × 注册表的对账），这里只挑出在跑的那些。
  let report = @instances.instances_report_with_settings()
  let runtime : Array[@json.JsonVal] = []
  let mut proc_only = 0
  for item in report.instances {
    if item.signature_id == "not-dsh" || item.signature_id == "no-signature" {
      continue
    }
    let pid = match item.pid {
      Some(p) => p
      None => continue
    }
    // 注册表里那一条（按 pid 对）：只取元数据（日志路径、是否 detach、启动时刻）
    let mut meta_pid = -1
    let mut meta_log = ""
    let mut meta_detached = false
    let mut meta_started = ""
    let mut meta_home = ""
    let mut meta_profile = ""
    for r in registry.entries {
      if r.pid == pid {
        meta_pid = r.pid
        meta_log = r.log_path
        meta_detached = r.detached
        meta_started = r.started_at
        meta_home = r.home
        meta_profile = r.profile
      }
    }
    if meta_pid < 0 {
      // /proc 有、注册表没有 = 外部起的实例
      proc_only = proc_only + 1
    }
    runtime.push(
      @json.JObj([
        ("pid", @json.jint(pid)),
        ("port", @json.jint(item.port)),
        ("home", @json.JStr(if meta_home == "" { match item.dsh_home { Some(h) => h; None => "" } } else { meta_home })),
        ("profile", @json.JStr(if meta_profile == "" { match item.profile { Some(p) => p; None => "" } } else { meta_profile })),
        ("startedAt", @json.JStr(meta_started)),
        ("logPath", @json.JStr(meta_log)),
        ("detached", @json.JBool(meta_detached)),
        ("registered", @json.JBool(meta_pid >= 0)),
        ("alive", @json.JBool(true)),
      ]),
    )
  }
  // 差异条数（注册表有、/proc 没有 = 陈旧记录；/proc 有、注册表没有 = 外部起的）
  let mut stale = 0
  for r in registry.entries {
    let mut seen = false
    for item in report.instances {
      match item.pid {
        Some(p) => if p == r.pid { seen = true }
        None => ()
      }
    }
    if !seen {
      stale = stale + 1
    }
  }
  let reconcile = @json.JObj([
    ("runtime", @json.jint(runtime.length())),
    ("registryOnly", @json.jint(stale)),
    ("procOnly", @json.jint(proc_only)),
  ])
  let archived : Array[@json.JsonVal] = []
  for r in archive.entries {
    archived.push(@store.archive_json(r))
  }
  // 回收站条目（第六轮契约第一节）：trash/ 下每一份删除进回收站的 profile 目录一条。
  // profile 名与删除时刻都从目录名切（按最后一个 '-'，profile 名自己允许带 '-'）；
  // 文件数与体积是递归数出来的，数不动给 null 并把原因写在 sizeSource 里 —— 不编。
  // home 是**删除那一刻记下来的**来源（trash-origins.json），恢复按它归位；
  // 没记来源的旧条目 home 给空串、原因写在 homeSource 里，不拿控制台自己的 home 冒充。
  let trash : Array[@json.JsonVal] = []
  for item in list_trash() {
    trash.push(
      @json.JObj([
        ("dir", @json.JStr(item.dir)),
        ("profile", @json.JStr(item.profile)),
        ("deletedAtMs", @json.int64_or_null(item.deleted_at_ms)),
        ("deletedAtSource", @json.JStr(item.deleted_at_source)),
        ("home", @json.JStr(item.home)),
        ("homeSource", @json.JStr(item.home_source)),
        ("fileCount", @json.int_or_null(item.file_count)),
        ("bytes", @json.int64_or_null(item.bytes)),
        ("sizeSource", @json.JStr(item.size_source)),
      ]),
    )
  }
  let notes : Array[String] = []
  match registry.note {
    Some(n) => notes.push(n)
    None => ()
  }
  match archive.note {
    Some(n) => notes.push(n)
    None => ()
  }
  match order.note {
    Some(n) => notes.push(n)
    None => ()
  }
  for n in last_started_notes {
    notes.push(n)
  }
  for n in job_notes {
    notes.push(n)
  }
  let job_items : Array[@json.JsonVal] = []
  for job in jobs {
    // 试跑实例还活不活着是**读数那一刻的进程事实**，不是作业文件里的事实：
    // stoppedAt 只说明我们收过它，反推不出「现在还在不在」。
    // 界面据此说「试跑实例还在跑（端口 X）」，判据必须来自这里。
    let trial_alive = match job.trial {
      Some(t) => process_alive(t.pid)
      None => false
    }
    job_items.push(
      @store.job_list_json_extra(job, [("trialAlive", @json.JBool(trial_alive))]),
    )
  }
  for bad in bad_jobs {
    job_items.push(@store.bad_job_json(bad))
  }
  let fields : Array[(String, @json.JsonVal)] = [
    // P1 对账结果：只记差异条数（注册表陈旧 N 条、/proc 有而注册表没有 M 条）
    ("reconcile", reconcile),
    // 构建信息：页脚显示「server <sha>」（scripts/gen-build-info.sh 生成）
    ("buildSha", @json.JStr(build_sha)),
    ("buildAt", @json.JStr(build_at)),
    ("stateDir", @json.JStr(paths.dir)),
    ("settingsPath", @json.JStr(paths.settings)),
    ("runtimePath", @json.JStr(paths.runtime)),
    ("archivePath", @json.JStr(paths.archive)),
    ("auditPath", @json.JStr(paths.audit)),
    ("orderPath", @json.JStr(paths.order)),
    ("trashDir", @json.JStr(paths.trash)),
    ("jobsDir", @json.JStr(paths.jobs)),
  ]
  // 生效的删除方式摆在 trashDir 旁边：一处说「进回收站落到哪」，一处说「现在是不是进回收站」
  for pair in delete_mode_fields() {
    fields.push(pair)
  }
  fields.push(("runtime", @json.JArr(runtime)))
  fields.push(("archive", @json.JArr(archived)))
  fields.push(("trash", @json.JArr(trash)))
  // 顺序表原样给出去（空数组就是「没拖过」）。前端拿到它之后怎么落到两组行上，
  // 是前端的事：这一端只负责「文件里是什么」，不在这里替页面排一遍。
  fields.push(("jobs", @json.JArr(job_items)))
  fields.push(("order", @store.order_json(order.ids)))
  fields.push(("lastStarted", @store.last_started_json(last_started)))
  fields.push(("notes", @json.jstr_array(notes)))
  @json.JObj(fields)
}

///|
/// 只答 GET。
pub async fn handle_console(
  req : @moonback.Request,
  res : @moonback.Responder,
  read_at : String,
) -> Unit {
  let verb = @localapi.method_name(req.meth)
  if verb != "GET" {
    send_method_not_allowed(res, "GET", verb, read_at)
    return
  }
  @localapi.send_ok(res, console_payload(), read_at)
}