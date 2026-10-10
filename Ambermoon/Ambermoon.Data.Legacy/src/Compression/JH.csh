namespace Ambermoon.Data.Legacy.Compression;

using Ambermoon.Data.Legacy.Serialization;

/// The JH encryption (Jurie Horneman's): every word is xor'ed with a key that changes from word to word. Encrypting
/// and decrypting are the same operation.
struct JH
{
    /// En- or decrypts `data` in place from `offset` on (a last single byte is handled as the upper byte of a word).
    static unsafe void Crypt(uint8[] data, uint16 key, int offset)
    {
        int length = data.Length;
        if (offset >= length)
            return;
        uint8* p = &data[offset]; // (checks the offset like an index)
        uint8* end = p + ((length - offset) & ~1); // the end of the whole words
        int d0 = key; // (16 bits: the sums below cannot overflow)
        if ((offset & 1) == 0)
        {
            // word by word (the elements of an array start at an even address); a word of memory is the high byte
            // first on the 68000 (big endian), the low byte first on a little-endian machine
            uint16 probe = 1;
            bool little = *(uint8*)&probe == 1;
            uint16* w = (uint16*)p;
            uint16* wend = (uint16*)end;
            if (little)
            {
                while (w < wend)
                {
                    *w ^= (uint16)((d0 >> 8) | (d0 << 8));
                    w += 1;
                    d0 = ((d0 << 4) + d0 + 87) & 0xffff;
                }
            }
            else
            {
                while (w < wend)
                {
                    *w ^= (uint16)d0;
                    w += 1;
                    d0 = ((d0 << 4) + d0 + 87) & 0xffff;
                }
            }
            p = (uint8*)w;
        }
        else
        {
            while (p < end)
            {
                *p ^= (uint8)(d0 >> 8);
                *(p + 1) ^= (uint8)d0;
                p += 2;
                d0 = ((d0 << 4) + d0 + 87) & 0xffff;
            }
        }
        if (((length - offset) & 1) != 0)
            *p ^= (uint8)(d0 >> 8);
    }

    /// En- or decrypts `data` in place.
    static void Crypt(uint8[] data, uint16 key)
    {
        Crypt(data, key, 0);
    }

    /// The rest of the reader (from its position to the end) en- or decrypted, as a new array. The reader is at its end
    /// afterwards.
    static uint8[] Crypt(ref DataReader reader, uint16 key)
    {
        var data = reader.ReadToEnd();
        Crypt(data, key, 0);
        return data;
    }
}
