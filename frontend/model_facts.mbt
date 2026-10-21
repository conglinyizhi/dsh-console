// 模型结构：各接口读数对应的 struct（ProfileFact / InstanceFact / JobFact / ConsoleFacts …）
// 与它们身上的小工具（evidence_text / job_result_line）。
//
// 2026-10-20 从 model.mbt 拆出来：结构定义是一份稳定的契约，与逐字段解析分开更好读。
// 只搬位置，函数体一个字没改。

///|
/// 这台机器上装着的一份 dsh（读数里的 dshCandidates 一项）。
///
/// active / running 都是后端给的事实，前端不按版本号自己推：
///   active  起实例（启动 / 重启）会用这一份
///   running 有在跑的实例，它的入口包就是这一份
/// 版本号相同、目录不同的两份 dsh 不是同一份（一份是软链、一份在别的全局根里），
/// 所以「是不是同一份」永远看后端怎么判。
pub(all) struct DshCandidate {
  version : String
  name : String
  dir : String
  /// 这份是怎么找到的（后端原样给，进悬停）
  source : String
  active : Bool
  running : Bool
} derive(Eq)

///|
pub extend DshCandidate with Eq::{not_equal, equal}

///|
pub(all) struct RuntimeFacts {
  dsh_version : String
  dsh_package_name : String
  dsh_source_label : String
  /// 这台机器上装着的 dsh（可能不止一份）。空数组 = 这一版读数里没有候选这一项
  dsh_candidates : Array[DshCandidate]
  /// 生效版本的状态：auto（没指定）/ pinned（按你指定的那一版）/ pin-missing（指定过、那份没了）。
  /// 空串 = 这一版读数里没有这一项（界面按「不知道」处理，不猜成 auto）
  dsh_pin_state : String
  /// 指定失效时后端给的那句人话；其余空串
  dsh_pin_note : String
  /// 这份 dsh 是怎么装上去的：pnpm / npm / yarn / unknown。
  /// 空串 = 这一版读数里没有这一项（不是「未知」——界面那一行要分开说）
  dsh_install_kind : String
  /// 凭什么这么判（后端原样给，进悬停）
  dsh_install_kind_source : String
  console_version : String?
  console_package_name : String
  console_version_source : String
  backend_runtime : String
  backend_version : String
  dsh_home : String
  dsh_home_source : String
  dsh_profile : String?
  platform : String
} derive(Eq)

///|
pub extend RuntimeFacts with Eq::{not_equal, equal}

///|
/// 一个候选版本（读数里的 versions 一项）。
///
/// 六个字段都是后端的判定，前端不自己再推：
///   prerelease    GitHub 的 release 标记 / registry 上版本号带 "-"（后端按各自的形状判）
///   latest        registry 的 dist-tags.latest 是不是它
///   next          registry 的 dist-tags.next 是不是它
///   installed     这台机器上装着这一版（与 dshCandidates 同一条链）
///   published_at  这一版的发布时间（ISO）：GitHub 的 published_at / registry 的 time[版本]。
///                 空串 = 这个源没给 —— 界面写「不知道」，**不拿拉取时刻顶替**
pub(all) struct ReleaseVersion {
  version : String
  prerelease : Bool
  latest : Bool
  next : Bool
  installed : Bool
  published_at : String
} derive(Eq)

///|
pub extend ReleaseVersion with Eq::{not_equal, equal}

///|
/// 一个来源问下来的结果。ok=false 时 error 是后端给的那句人话（超时 / 连不上 / 格式不对）。
pub(all) struct ReleaseSource {
  id : String
  ok : Bool
  /// 这个源这一趟花了多少毫秒（后端量的，含 curl 起进程与解析）
  ms : Int32
  error : String
  /// 这个源给出几条版本
  count : Int32
} derive(Eq)

///|
pub extend ReleaseSource with Eq::{not_equal, equal}

///|
/// 版本来源读数（GET /api/local/dsh-releases）。
///
/// chosen 空串 = 三个源全没答上来（那时 versions 是空的 —— 界面据此换一句话，
/// 不许把「没问到」写成「没有新版」）。
pub(all) struct ReleasesFacts {
  chosen : String
  /// 采用那个源给的版本，按版本号从新到旧
  versions : Array[ReleaseVersion]
  /// registry 的 dist-tags：latest / next（GitHub 没有这两条，空串 = 没有）
  latest : String
  next : String
  /// 这台机器上装着哪几版 dsh（与 runtime 的 dshCandidates 同一条链）
  installed : Array[String]
  /// 三个源各自的结果与耗时，顺序固定 github → npm → mirror
  sources : Array[ReleaseSource]
  read_at : String
  // ── 缓存三格（design/ops-maintenance-jobs.md §10.1）──
  //
  // 后端起来就在后台拉一次版本列表，这条接口只读缓存、秒回。这三格说的都是**那一趟拉取**：
  /// loading（有一趟在路上）/ ready（有答案、现在没在拉）/ failed（拉到了却没有答案）
  state : String
  /// 最近一次拉到的时刻（ISO；空串 = 还没拉到过）
  fetched_at : String
  /// 这份缓存是否超过 10 分钟
  stale : Bool
  /// 这一趟没拿到答案的原因（三个源都没答上来时是各源的原话；空串 = 有答案）
  fetch_error : String
} derive(Eq)

///|
pub extend ReleasesFacts with Eq::{not_equal, equal}

///|
pub(all) struct ProfileBundles {
  declared : Int32
  installed : Int32
  missing : Array[String]
} derive(Eq)

///|
pub extend ProfileBundles with Eq::{not_equal, equal}

///|
/// 一份配置快照（design/ops-maintenance-jobs.md 第 16.2 节）。
///
/// 后端每只 profile 给一个 snapshots 数组，从新到旧。at 是 ISO 时刻；
/// reason 是拍的时候写的那句话；files / bytes 是这一份里存了几个文件、共多少字节。
/// 没有 snapshots 这一项（旧后端）时按空数组解析，界面走空态。
pub(all) struct SnapshotFact {
  id : String
  at : String
  reason : String
  files : Int32
  /// meta.json 里记的字节数。接口给的是数字，按 Double 收（与回收站条目同一口径）
  bytes : Double
} derive(Eq)

///|
pub extend SnapshotFact with Eq::{not_equal, equal}

///|
/// 这只 profile **最近一次启动**的结局（design/design-fixes.md §26.1）。
///
/// 后端从审计流水（audit.jsonl）里取最近一条启动记录（start-instance 或 restart-instance，
/// 见 design/design-fixes.md §27.1），成败由那一笔自己说：
///   ok = false → 那一次失败了。它又是最近一条，所以「失败之后没有成功过」自然成立 ——
///                真有过一次成功，那一次就是最近那一条。
///   ok = true  → 最近一次是成功的，不点红灯，按运行中 / 有警告 / 已停止这三档。
///
/// None = 审计里没有这只 (home, profile) 的记录。**没有证据就不点红灯**：
/// 与「上一次失败了」不是一件事，所以用 Option 而不是拿 ok: true 或 false 顶上。
pub(all) struct ProfileLastStart {
  ok : Bool
  /// 这一笔的时刻（UTC ISO）。空串 = 读数里没给（不编一个时间出来）
  at : String
  /// 失败码（conflict / not-found / spawn-failed / bad-params …）；成功时空串
  code : String
  /// 失败时后端写下的那句人话；成功时空串
  message : String
  /// 那一笔带的 home；空串 = 那一笔没带（老记录）
  home : String
} derive(Eq)

///|
pub extend ProfileLastStart with Eq::{not_equal, equal}

///|
pub(all) struct ProfileFact {
  name : String
  is_current : Bool
  patch_exists : Bool
  patch_lines : Int32
  lock_exists : Bool
  lock_mtime : String?
  bundles : ProfileBundles
  /// 用户给这只 profile 写的备注（<profile 目录>/.dsh-note.txt）。空串 = 没写备注。
  note : String
  /// 备注的读取口径 / 读不到的原因，后端原样给；空串表示没什么要说的
  note_source : String
  /// 这只 profile **目录**的最近改动时刻（mtime，毫秒时间戳）。None = 读不到。
  ///
  /// 为什么是「最近改动」而不是「创建时间」：多数文件系统上可靠的创建时间拿不到
  /// （ctime 会在 chmod / 改名时变，birth time 不通用）。目录 mtime 是能拿到、
  /// 且不会骗人的那一个 —— 刚派生出来的 profile 一定是最新的，所以它同时回答了
  /// 「哪个是刚弄的」。卡上那一格的标签因此写「最近改动」，不许写成「创建时间」。
  dir_mtime_ms : Double?
  /// 这个时刻从哪来 / 为什么读不到，后端原样给（dirMtimeSource）；
  /// 字段**根本不在响应里**时由前端补一句说明（见 parse_profiles），别处不改写它。
  dir_mtime_source : String
  // ── 配置 home（design/deep-home-isolation.md 第 4 节）──
  //
  // 后端每只 profile 给一个 home 对象：{ kind, path, profileDir, createdAt }。
  //   kind = "isolated" 这只 profile 有自己的隔离 home（<DSH_CONSOLE_HOMES_ROOT>/<名字>/）
  //   kind = "shared"   与控制台共用 DSH_HOME
  // 空串 = 这一版后端没给这一项（按「读不到」处理，界面不猜一个归属出来）。
  /// isolated / shared / 空串（读数里没有）
  home_kind : String
  /// 隔离 home 根，或控制台的 DSH_HOME
  home_path : String
  /// 实例真正读配置的目录（<path>/profiles/<名字>）
  home_profile_dir : String
  /// 隔离记录里的时刻；共用那一档没有（后端给 null）
  home_created_at : String?
  /// 后端给的一句判断依据（homeKindSource）；空串 = 这一版后端没给
  home_kind_source : String
  /// 补包会在 profile 目录里跑的那条命令（design/design-fixes.md §39）：
  /// 后端按 lock 文件选好了（pnpm / npm install --prefer-offline）。空串 = 这一版后端没给。
  repair_command : String
  /// 指向 profile 之外、且目标存在的软链接条数（design/design-fixes.md §60.1）：
  /// 派生副本前用它决定要不要先告知「藕断丝连」。
  external_links : Int32
  /// 解析不到目标的链接条数（只进读数供排查，界面不显示）
  broken_links : Int32
  // ── 试跑那一块的判据（design/ops-maintenance-jobs.md §9.3）──
  //
  // None = 这一版后端没给这一项（那时不拿它判不可用，宁可让试跑自己去撞失败）。
  /// package.json 在、且读得动（false = 这只配置读不到）
  package_json_ok : Bool?
  /// dsh.profile.bundles 里有没有 @deepseek-ai/dsh-web-app（false = 命令行型，没有网页入口）
  web_app : Bool?
  // ── 配置快照（design/ops-maintenance-jobs.md §16.2）──
  /// 这只 profile 的快照列表，从新到旧。空数组 = 还没拍过（或这一版后端没给这一项，
  /// 那时 snapshots_source 里会是一句前端补的说明，而不是后端的原因）。
  snapshots : Array[SnapshotFact]
  /// 快照读数的来源 / 读不到的原因（后端原样给）
  snapshots_source : String
  // ── 最近一次启动的结局（design/design-fixes.md §26.1）──
  /// None = 审计流水里没有这一只的记录（或这一版后端还没给这个字段）
  last_start : ProfileLastStart?
  /// 上面那一格的来源 / 为什么没有：取的是审计里哪一条、按什么对上的（后端原样给）
  last_start_source : String
} derive(Eq)

///|
pub extend ProfileFact with Eq::{not_equal, equal}

///|
pub(all) struct ProfilesFacts {
  dsh_home : String
  dsh_home_source : String
  profiles_root : String
  current_profile : String?
  profiles : Array[ProfileFact]
} derive(Eq)

///|
pub extend ProfilesFacts with Eq::{not_equal, equal}

///|
/// 预览里的一边（源或目标）：名字、现在所在的目录、home 归属、配置读不读得到。
pub(all) struct PromoteSide {
  name : String
  dir : String
  home_kind : String
  home_path : String
  profile_dir : String
  config_ok : Bool
} derive(Eq)

///|
pub extend PromoteSide with Eq::{not_equal, equal}

///|
/// 覆盖项里的一条（新增或移除的那一条）：id 与原文。
pub(all) struct PromotePatchEntry {
  id : String
  text : String
} derive(Eq)

///|
pub extend PromotePatchEntry with Eq::{not_equal, equal}

///|
/// 同 id 两边原文不一样的那一条：两边全文都在，界面并排摆。
pub(all) struct PromotePatchChange {
  id : String
  source_text : String
  target_text : String
} derive(Eq)

///|
pub extend PromotePatchChange with Eq::{not_equal, equal}

///|
/// 同名不同版本的一个本地包。
pub(all) struct PromotePackageVersion {
  name : String
  source_version : String
  target_version : String
} derive(Eq)

///|
pub extend PromotePackageVersion with Eq::{not_equal, equal}

///|
/// 一次预览的全部读数。
pub(all) struct PromotePreview {
  source : PromoteSide
  target : PromoteSide
  /// 源里有、目标里没有的文件名
  files : Array[String]
  /// 源里有、会被写过去的文件名
  files_written : Array[String]
  /// 目标有、源里没有（不删）
  files_target_only : Array[String]
  bundles_added : Array[String]
  bundles_removed : Array[String]
  bundles_reordered : Bool
  bundles_from : Array[String]
  bundles_to : Array[String]
  patches_added : Array[PromotePatchEntry]
  patches_changed : Array[PromotePatchChange]
  patches_removed : Array[PromotePatchEntry]
  /// 没有 id 的覆盖项条数（那几条只能按整段原文比）
  patches_anonymous : Int32
  packages_added : Array[String]
  packages_mismatch : Array[PromotePackageVersion]
  /// 非空就不许应用（后端给的原话）
  blockers : Array[String]
  /// 算的时候读不到的地方（后端给的原话）
  notes : Array[String]
} derive(Eq)

///|
pub extend PromotePreview with Eq::{not_equal, equal}

///|
/// 实例对应的 profile 的健康读数（profileHealth，第七轮契约新增）。
///
/// 只报两个事实：缺几个包、有没有 cordis.patch.yml —— 卡片上那颗状态灯「黄」的
/// 成因 c 就是它们（契约里写死的判据）。包名清单不在这里：它在 profiles 读数里。
pub(all) struct InstanceHealth {
  missing_bundles : Int32
  has_patch : Bool
} derive(Eq)

///|
pub extend InstanceHealth with Eq::{not_equal, equal}

///|
/// 同一只进程的另一个监听端口（读数里的 alsoPorts 一项）。
///
/// 后端按 pid 把条目归并成一行：只有主端口那一条成行，其余端口收在这里当附注。
/// 卡片上不显示、也不因它变色 —— 那一行说的是「这一只实例」，不是「一个端口」。
pub(all) struct AlsoPortFact {
  port : Int32
  http_status : Int32?
  /// 这个端口命中的判据（没命中是空串）
  signature_id : String
  /// 后端给的一句人话：这个端口是什么、这一次探测拿到了什么
  note : String
} derive(Eq)

///|
pub extend AlsoPortFact with Eq::{not_equal, equal}

///|
pub(all) struct InstanceFact {
  id : String
  port : Int32
  url : String
  http_status : Int32
  signature_id : String
  signature_describe : String
  profile : String?
  dsh_home : String?
  uptime_seconds : Int32?
  /// 这只实例**真实**的启动时刻（UTC ISO）。后端从进程起始时间推出来，不是控制台记的。
  /// None = 读不到 —— 卡片第二行的「上次启动」这时才退回控制台自己的记录
  /// （runtime.json 的 startedAt / audit.jsonl 的 start-instance）；两处都没有就不写那一行，
  /// **绝不拿一个别的时刻顶上**。
  started_at : String?
  /// 入口包 …/node_modules/@deepseek-ai/dsh/package.json 的 version；读不到是 None
  version : String?
  /// 下面几条都是「这个值是从哪读出来的 / 为什么读不到」，原样来自后端，不在前端编
  version_source : String
  profile_source : String
  dsh_home_source : String
  /// 这只实例用的 home 的归属：trial / isolated / shared（§11.1）。
  /// 空串 = 这一版后端没给，或 DSH_HOME 读不到 —— 抽屉那一格退回 profile 读数，不猜。
  home_kind : String
  /// 上面那一档凭什么判的（后端原样给，直接进悬停）
  home_kind_source : String
  /// 进程级原因码：port-join / port-arg / process-gone / fd-unreadable / cmdline-unreadable / unscanned
  process_reason_code : String
  process_reason : String
  /// 运行时登记（$XDG_STATE_HOME/dsh-console/runtime.json）里有这一条 → 由本控制台启动。
  /// 后端把登记结果并进 instances 的这个字段上（见 README「还缺什么」一节）；
  /// 字段不在就是 false —— 宁可少一个标记，也不拿 profile 名字去猜。
  console_started : Bool
  /// 带令牌的完整地址（`http://<host>:<port>/?token=…`），新标签页打开它才能过首次握手。
  /// null / 字段不在 = 读不到令牌：这时**不拿裸地址冒充**（裸地址打开就是一个 401 页面）。
  web_url : String?
  /// 令牌从哪来，或为什么读不到（后端原样给；这一版后端还没这个字段时也补一句人话）。
  web_url_source : String
  /// 状态灯的三档（第七轮契约）：running / fault / starting。
  /// None = 这一版后端还没给这个字段（或给了个不是字符串的值）——
  /// 这时**不许猜颜色**：卡上那颗灯走「未知」那一档，抽屉里说清是后端没给。
  state : String?
  /// 为什么是这个状态（读数原样给；界面不直接渲染它，见 state_reason_of）。
  state_reason : String
  /// 实例对应的 profile 健康读数；None = 这一版后端没给 profileHealth。
  /// None 与「给了但缺 0 个包」不是一件事，所以用 Option 而不是拿 0 顶上。
  profile_health : InstanceHealth?
  /// 同一只进程的其余监听端口。空数组 = 这只进程只听着这一个端口，
  /// 或者这一版后端还没做归并（那一种会各占一行，不会进这里）
  also_ports : Array[AlsoPortFact]
} derive(Eq)

///|
pub extend InstanceFact with Eq::{not_equal, equal}

///|
pub(all) struct InstancesFacts {
  sources : Array[String]
  candidate_count : Int32
  probe_hits : Int32
  process_note : String
  signature_ids : Array[String]
  instances : Array[InstanceFact]
} derive(Eq)

///|
pub extend InstancesFacts with Eq::{not_equal, equal}

///|
/// 进程扫描的一条读数。当前界面不直接渲染它（运行中实例的主口径是端口 + HTTP 签名，
/// Vue 版同样没用这个接口），数据层照样解析，免得接口在白名单里却没有客户端。
pub(all) struct ProcessFact {
  pid : Int32
  port : Int32
  profile : String?
  uptime_seconds : Int32?
} derive(Eq)

///|
pub extend ProcessFact with Eq::{not_equal, equal}

///|
pub(all) struct ProcessesFacts {
  proc_root : String
  scanned : Int32
  matcher : String
  instances : Array[ProcessFact]
} derive(Eq)

///|
pub extend ProcessesFacts with Eq::{not_equal, equal}

///|
/// 级别只在接口真读得出时才有值：error / warn，其余是 None（界面写「··」并压成次级灰）。
pub(all) struct LogLine {
  time : String?
  level : String?
  text : String
} derive(Eq)

///|
pub extend LogLine with Eq::{not_equal, equal}

///|
pub(all) struct LogsFacts {
  source : String
  label : String?
  kind : String
  instance_port : Int32?
  detected_instances : Int32?
  path : String?
  home_source : String?
  effective_tail : Int32
  max_tail : Int32
  read_ok : Bool
  error_code : String?
  read_error : String?
  file_size : Int32?
  window_bytes : Int32
  lines : Array[LogLine]
  truncated : Bool
  truncated_note : String?
  tail_note : String?
} derive(Eq)

///|
pub extend LogsFacts with Eq::{not_equal, equal}

///|
/// 运行时登记里的一条：控制台自己起过的实例（runtime.json）。
pub(all) struct ConsoleRuntime {
  pid : Int32
  port : Int32
  profile : String
  alive : Bool
} derive(Eq)

///|
pub extend ConsoleRuntime with Eq::{not_equal, equal}

///|
/// 一条归档记录（archive.json）：只记「这只 profile 已归档」，磁盘上的目录不动。
///
/// 第二轮起没有「已合并」标记了（使用者的决定）：归档就是归档，成没成果不在这条记录里。
/// 旧的 archive.json 里可能还带着 merged 字段，读的时候直接忽略 —— 少读一个字段不算错。
///
/// home 是这份档案属于哪个 home（多 home 之后，一份档案的身份是 home + 名字）。
/// 空串 = 这条记录没有 home：本次改动之前写下的旧记录 —— 那种记录按名字参与匹配，
/// 见 state.mbt 的 archive_record_matches_row。**字段不在就是空串**，不拿别的值顶上。
pub(all) struct ConsoleArchive {
  profile : String
  home : String
  archived_at : String
} derive(Eq)

///|
pub extend ConsoleArchive with Eq::{not_equal, equal}

///|
/// 回收站里的一条（GET /api/local/console 的 trash[]，第六轮契约）。
///
/// profile 名与删除时刻是后端从目录名（`<profile>-<epochMs>`）里切出来的：
/// profile 名自己允许带 `-`，所以按**最后一个** `-` 切 —— 切不出来时后端给的是
/// 「原目录名 + 时间 null」，这里照收，不在前端猜一个时刻出来。
pub(all) struct ConsoleTrash {
  /// trash 下的目录名，恢复 / 彻底删除时的 dir 参数
  dir : String
  profile : String
  /// 删除时刻（毫秒时间戳）；None = 目录名里读不出来
  deleted_at_ms : Double?
  /// 上面那个时间的来源，或读不出来的原因（后端原样给）
  deleted_at_source : String
  /// 递归数出来的普通文件个数；None = 数不动
  file_count : Int32?
  /// 递归求和的字节数；None = 数不动
  bytes : Double?
  /// 文件数与体积的来源，或数不动的原因（后端原样给）
  size_source : String
} derive(Eq)

///|
pub extend ConsoleTrash with Eq::{not_equal, equal}

///|
/// 一条「上次启动」读数（GET /api/local/console 的 lastStarted[]）。
///
/// 后端把两份控制台记录并成一张表（runtime.json 的 startedAt、audit.jsonl 里
/// start-instance 且成功的那一笔），同一个 id 只留最近的那一条。前端只负责按 id 查。
pub(all) struct LastStartedFact {
  /// 行 id，与 Row.id 同一套：port:<端口号> / profile:<名字>
  id : String
  /// 启动时刻（UTC ISO，后端原样给）。空串 = 这一条没有可用时刻，不渲染。
  at : String
  /// 这个时刻从哪读出来的（人话，直接进悬停）
  source : String
} derive(Eq)

///|
pub extend LastStartedFact with Eq::{not_equal, equal}

///|
/// 一步的 evidence 对象压成一行「键=值 | 键=值」：只进悬停，不在正文里摊开。
fn evidence_text(step : Map[String, Json]) -> String {
  let parts : Array[String] = []
  for entry in step.iter() {
    let (key, value) = entry
    let text = match value {
      Json::String(s) => s
      _ => ""
    }
    parts.push(key + "=" + text)
  }
  join_with(parts, " | ")
}

///|
/// 一条作业的一句话结果：某一步的结论（维护页作业卡第二行用它）。
fn job_result_line(steps : Array[JobStepFact]) -> String {
  // 从后往前找第一条有结论的步骤：最后落定的那一步才是「现在到哪了」
  let mut text = ""
  for step in steps {
    if step.note != "" && step.state != "not-run" {
      text = step.note
    }
  }
  text
}

///|
/// 维护作业的一步（后端 jobs[].steps[] 的一项）。
///
/// evidence 已经在解析时拼成一行「键=值 | 键=值」：界面只把它放进悬停，
/// 不在正文里摊开（§6：目录路径 / 命令原文不进正文）。
pub(all) struct JobStepFact {
  key : String
  /// running / passed / failed / skipped / not-run。不认识的取值原样留着，
  /// 界面按「没验到」显示 —— 不认识的不能读成通过。
  state : String
  at : String
  note : String
  evidence : String
} derive(Eq)

///|
pub extend JobStepFact with Eq::{not_equal, equal}

///|
/// 一条维护作业（GET /api/local/console 的 jobs[]）。
///
/// unreadable = true 的那条是「记录读不出来」：只有 id 与 reason，没有步骤表。
/// 这种记录也必须出现在列表里（§3 第 2 条），不能因为它读不出来就当作不存在。
pub(all) struct JobFact {
  id : String
  kind : String
  title : String
  created_at : String
  updated_at : String
  step : String
  steps : Array[JobStepFact]
  anchor_version : String
  anchor_dir : String
  target_version : String
  target_dir : String
  /// 试跑用哪一只 profile（job-start 时选定）
  profile : String
  /// 开工前 dsh-pin.json 里指定过哪一版（空串 = 开工前没指定，或者那份文件读不出来）
  pin_before_version : String
  /// 开工前到底有没有那份文件。**与「有文件但里面是空」分开**：
  /// 回滚那句「恢复成开工前」到底意味着「写回一条」还是「删掉」，全看这一格
  pin_before_existed : Bool
  /// 试跑实例（pid ≤ 0 = 还没有试跑过）
  trial_pid : Int32
  trial_port : Int32
  trial_url : String
  trial_profile : String
  /// 试跑用的一次性 home（design/deep-home-isolation.md 第 6 节）。空串 = 旧记录
  /// （第三版之前试跑借的是当时那份真实 home）
  trial_home : String
  /// home 的归属：trial = 这次作业的一次性 home；空串 = 旧记录
  trial_home_kind : String
  /// 复制到一次性 home 里的那份 profile 目录（<home>/profiles/<名字>）
  trial_profile_copy : String
  trial_started_at : String
  /// 我们收过它的时刻（空串 = 没收到过）。**它不说「现在还在不在」**
  trial_stopped_at : String
  /// 读数那一刻这只试跑实例还活着吗（后端现查进程表，见 console_api 的 trialAlive）。
  /// 这一格是「试跑实例还在跑」唯一可信的判据 —— stoppedAt 反推不出来
  trial_alive : Bool
  /// 用户给的结论：good / bad / later（空串 = 还没给）
  verdict_value : String
  unreadable : Bool
  reason : String
} derive(Eq)

///|
pub extend JobFact with Eq::{not_equal, equal}

///|
/// 控制台自己的状态读数。这一份不在契约里那五个只读接口之列：
/// runtime.json / archive.json 是两份状态文件，浏览器读不到文件系统，
/// 后端为此单开了一个只读端点（GET /api/local/console）。
pub(all) struct ConsoleFacts {
  /// 服务端构建 sha / 时刻（scripts/gen-build-info.sh 生成；空串 = 这一版后端没给）
  build_sha : String
  build_at : String
  state_dir : String
  settings_path : String
  archive_path : String
  /// 生效的删除方式：true = 删了进回收站，false = 硬删。None = 这一版后端没给这个字段。
  ///
  /// 为什么从这儿取：设置是懒加载的（进过设置页才有值），而删除确认框在打开之前
  /// 就得说清「删了会怎样」。这个端点在页面加载时就读了，所以它总能给一个生效值。
  delete_to_trash : Bool?
  /// 上面那个值来自文件还是默认（后端原样给）。空串 = 后端没给这一项。
  delete_to_trash_source : String
  runtime : Array[ConsoleRuntime]
  archive : Array[ConsoleArchive]
  /// 回收站条目（后端按删除时刻倒序给，最近删的在前）
  trash : Array[ConsoleTrash]
  /// 手动排序的顺序表（order.json 的原样：一个行 id 的数组，顺序即使用者拖出来的顺序）。
  ///
  /// **空数组 = 没拖过** —— 那时列表走自动排序（运行中按实例、已停止按最近改动降序）。
  /// 字段不在（这一版后端还没有它）与空数组在这里是同一件事：都退回自动排序，
  /// 因为两者的行为要求完全一样：没有顺序可用就用自动的。
  order : Array[String]
  /// order.json 的路径（后端原样给；空串 = 这一版后端没给）。只在提示里出现。
  order_path : String
  /// 每只实例 / 每只 profile 最后一次被启动的时刻（后端已按 at 降序并去重）
  last_started : Array[LastStartedFact]
  /// 维护作业（后端按 createdAt 倒序给；读不出来的记录也在这张表里，unreadable=true）
  jobs : Array[JobFact]
  /// 响应里**有没有** jobs 这个字段。与「字段在、但为空」分开：字段不在 = 这一版后端
  /// 还没有作业读数（不能说成「还没有作业」）
  jobs_present : Bool
  /// 作业文件的落盘目录（只在「记录读不出来」那一类提示里出现）
  jobs_dir : String
  /// 响应里**有没有** trash 这个字段。
  ///
  /// 与「字段在、但为空」分开：字段不在 = 这一版后端还没有这个读数（页面上要说清是读不到，
  /// 不是「回收站是空的」）；字段在且为空 = 回收站真的是空的。两种都写成空态，
  /// 就是把「还没读到」说成了「没有」✗（加载态与空态分开同一条道理）。
  trash_present : Bool
  notes : Array[String]
} derive(Eq)

///|
pub extend ConsoleFacts with Eq::{not_equal, equal}
