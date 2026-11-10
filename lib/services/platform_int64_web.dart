/// Web 端 PlatformInt64 为 BigInt；返回 dynamic 以兼容 VM 侧的静态分析。
dynamic toPlatformInt64(int value) => BigInt.from(value);
