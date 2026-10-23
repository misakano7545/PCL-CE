namespace PCL;

/// <summary>
///     区域功能限制策略。
///     上游 PCL CE 会针对中国大陆（以及无法判定区域）禁用 Minecraft 下载、补全、修复与整合包安装，
///     本构建已移除该限制：任何区域一律放行，不再进行任何区域判定或拦截。
/// </summary>
internal static class RestrictedFeaturePolicy
{
    /// <summary> 区域限制已移除，因此不存在受限区域。 </summary>
    internal static bool IsRestricted => false;

    /// <summary> 区域限制已移除，此方法恒返回 True；<paramref name="showHint" /> 不再产生任何提示。 </summary>
    internal static bool Check(string feature, bool showHint = true) => true;

    /// <summary> 区域限制已移除，不再抛出取消异常。 </summary>
    internal static void ThrowIfRestricted(string feature)
    {
    }
}
