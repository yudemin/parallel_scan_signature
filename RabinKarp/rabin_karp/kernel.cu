#include <Windows.h>
#include <iostream>
#include <fstream>
#include <fstream>
#include <vector>
#include <chrono> 
#include <iomanip> 
#include <mutex>
#include <string.h>


#include "cuda.h"
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

using namespace std;
__global__ void scan(unsigned char* byte_file, unsigned char* sign, int sign_size, int part_size, int file_size, int threads_per_block, char* mask, int q)
{
    int sign_hash = 0; // хеш для сигнатуры
    int text_hash = 0; // хеш для окна текста
    int d = 256; // размер алфавита
    int h = 1; // значение d^(sign_size-1)
    for (int i = 0; i < sign_size - 1; i++)
        h = (h * d) % q;

    int thread = blockIdx.x * threads_per_block * part_size; // номер текущего потока
    int i = threadIdx.x;
    int offset = thread + (i * part_size); // вычисление сдвига по файлу

    /* вычисление хеша для сигнатуры и первого окна текста */
    for (int i = 0; i < sign_size; i++)
    {
        sign_hash = (d * sign_hash + sign[i]) % q;
        text_hash = (d * text_hash + byte_file[offset + i]) % q;
    }
    int sign_shift = 0;
    while ((sign_shift <= part_size) && (offset + sign_shift < file_size - sign_size)) { // цикл алгоритма с учетом перекрытий
        bool sign_check = true;
        /* если хеши совпадают то начинается дополнительная проверка, чтобы исключить ложные срабатывания */
        if (sign_hash == text_hash)
        {
            /* посимвольно сверяем сигнатуру с окном текста методом прямого поиска */
            for (int i = 0; i < sign_size; i++)
            {
                if (byte_file[offset + sign_shift + i] != sign[i])
                {
                    if (mask[i] == '1') // проверяем, является ли байт ключевым
                    {
                        sign_check = false;
                        break;
                    }
                    else
                    {
                        continue;
                    }
                }
            }
            if (sign_check == true)
            {
                /* сигнатура найдена */
                //printf("sign found on address:  %04x (block: %d, tread: %d)\n", (offset + sign_shift), blockIdx.x, threadIdx.x);
            }
        }
        /* вычисляется хеш для нового окна текста */
        text_hash = (d * (text_hash - byte_file[offset + sign_shift] * h) + byte_file[offset + sign_shift + sign_size]) % q; 
        sign_shift++;
        /* полученное значение text_hash может быть отрицательным, в этом случае добавляем q */
        if (text_hash < 0)
        {
            text_hash = (text_hash + q);
        }
    }
}

int main()
{
    printf("Rabin-Karp algoritm on GPU\n");
    /* процесс считывания данных */
    const char* filename = "D:/_Politech/ScanSignature/RealtekHDAudio_Rus_Setup.exe"; // используется EXE звукового драйвера, т.к. самый большой найденный EXE
    ifstream file; // файл открывается для бинарного считывания 
    file.open(filename, ios_base::binary);
    file.seekg(0, ios::end); // определение длины файла
    size_t fileSize = file.tellg();
    file.seekg(0, ios::beg);
    vector<byte> byte_file(fileSize, 0); // создание вектора, в котором будут хранится все байты из файла 
    file.read(reinterpret_cast<char*>(&byte_file[0]), fileSize); // считывание     
    file.close(); // файл закрывается
   
    vector<unsigned char> sign_buffer = { 0x80, 0x3E, 0x00, 0x0F }; // объявление сигнатуры 
    char mask_[20] = "1111100000000000"; // объявление маски
    int sign_size = sign_buffer.size();
    int file_size = byte_file.size();

    auto start = chrono::high_resolution_clock::now(); // замер времени для инициализации
    /* запись файла в память GPU */
    unsigned char* bytefile;
    cudaMallocManaged(&bytefile, file_size * sizeof(char));
    for (int i = 0; i < file_size; i++) {
        bytefile[i] = byte_file[i];
    }
    /* запись сигнатуры в память GPU */
    unsigned char* sign;
    cudaMallocManaged(&sign, sign_size * sizeof(char));
    for (int i = 0; i < sign_size; i++) {
        sign[i] = sign_buffer[i];
    }
    /* запись маски в память GPU */
    char* mask;
    cudaMallocManaged(&mask, sign_size * sizeof(char));
    for (int i = 0; i < sign_size; i++) {
        mask[i] = mask_[i];
    }

    auto stop = chrono::high_resolution_clock::now();
    auto duration = chrono::duration_cast<chrono::milliseconds>(stop - start);
    printf("sign: %s\nmask: %s\n", sign, mask);
    printf("initialising time: %d milliseconds.\n", duration.count());

    /* инициализация параметров */
    int treads[5] = { 256, 512, 1024, 2048, 4096 }; // массив с количеством потоков для каждого выполнения бенчмарка
    int threads_ = 0;
    int blocks = 16;

    int q = 47; // любое простое число
    for (int i = 0; i < 5; i++)
    {
        threads_ = treads[i];
        int part_size = file_size / threads_;
        int threads_per_block = threads_ / blocks;
        auto start = chrono::high_resolution_clock::now();
        scan <<<blocks, threads_per_block >>> (bytefile, sign, sign_size, part_size, file_size, threads_per_block, mask, q); // вызов функции на GPU 
        cudaDeviceSynchronize();  // ожидание завершения всех потоков
        auto stop = chrono::high_resolution_clock::now();
        auto duration = chrono::duration_cast<chrono::milliseconds>(stop - start);
        printf("for %d blocks and %d treads execution time: %d milliseconds.\n", blocks, threads_, duration.count());
    }
    /* освобождение памяти */
    cudaFree(bytefile);
    cudaFree(sign);
    cudaFree(mask);
    cout << "\npress enter for exit";
    cin.ignore();

}

