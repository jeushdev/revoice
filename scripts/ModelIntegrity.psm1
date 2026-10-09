#requires -Version 7.0
Set-StrictMode -Version Latest

# Streaming verification keeps the 584 MB Gemma file out of managed memory.
if (-not ('Revise.ModelIntegrity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Security.Cryptography;

namespace Revise {
    public sealed class IntegrityResult {
        public long SizeBytes { get; set; }
        public string Sha256 { get; set; }
        public string Crc32c { get; set; }
    }
    public static class ModelIntegrity {
        private static readonly uint[] Table = BuildTable();
        private static uint[] BuildTable() {
            var table = new uint[256];
            for (uint i = 0; i < 256; i++) {
                uint value = i;
                for (int bit = 0; bit < 8; bit++)
                    value = (value >> 1) ^ ((value & 1) != 0 ? 0x82F63B78u : 0);
                table[i] = value;
            }
            return table;
        }
        public static IntegrityResult Inspect(string path) {
            using (var input = File.OpenRead(path))
            using (var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256)) {
                var buffer = new byte[65536];
                uint crc = 0xffffffffu;
                long size = 0;
                int count;
                while ((count = input.Read(buffer, 0, buffer.Length)) > 0) {
                    hash.AppendData(buffer, 0, count);
                    for (int i = 0; i < count; i++)
                        crc = Table[(crc ^ buffer[i]) & 255] ^ (crc >> 8);
                    size += count;
                }
                crc ^= 0xffffffffu;
                var checksum = new byte[] { (byte)(crc >> 24), (byte)(crc >> 16),
                    (byte)(crc >> 8), (byte)crc };
                return new IntegrityResult {
                    SizeBytes = size,
                    Sha256 = BitConverter.ToString(hash.GetHashAndReset()).Replace("-", "").ToLowerInvariant(),
                    Crc32c = Convert.ToBase64String(checksum)
                };
            }
        }
    }
}
'@
}

function Get-ModelIntegrity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)
    [Revise.ModelIntegrity]::Inspect([IO.Path]::GetFullPath($LiteralPath))
}

Export-ModuleMember -Function Get-ModelIntegrity
