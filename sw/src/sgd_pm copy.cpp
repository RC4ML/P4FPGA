// Copyright (C) 2017 Zeke Wang- Systems Group, ETH Zurich

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.

// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.
//*************************************************************************
/*
zipml_data_representation is mainly 
*/
//#ifndef ZIP_SGD_PM_CPP
//#define ZIP_SGD_PM_CPP

#include <stdlib.h>     /* srand, rand */
#include <time.h>       /* time */
#include <string.h>
#include <iostream>
#include <iomanip>
#include <fpga/XDMA.h>
#include <fpga/XDMAController.h>

using namespace std;

#include "sgd_pm.h"

#define AVX2_EN
#define CPU_BINDING_EN
#define BITS_OF_CL      512
#define NUM_BANKS       8
#define BITS_OF_BANK    (BITS_OF_CL/NUM_BANKS)
#define ENGINE_NUM		8
#define BITS_NUM		8
#define WORKER_NUM 		1

//#ifdef AVX2_EN
//#include "hazy/vector/mlweaving.h"      //mlweaving_8mr mlweaving_8mr_avx2     mlweaving mlweaving_avx2
//#include "hazy/vector/dot_mlweaving_avx2.h"      //mlweaving_8mr mlweaving_8mr_avx2     mlweaving mlweaving_avx2
/*
#include "hazy/vector/operations-inl_avx2.h"
#include "hazy/vector/scale_add-inl_avx2.h"
#include "hazy/vector/dot-inl_avx2.h"        //#include "hazy/vector/dot-inl.h" //
#else
#include "hazy/vector/operations-inl.h"
#include "hazy/vector/scale_add-inl.h"
#include "hazy/vector/dot-inl.h"
#endif

#ifdef CPU_BINDING_EN
#include "hazy/thread/thread_pool-inl_binding.h"
#else
#include "hazy/thread/thread_pool-inl.h"
#endif

#include "hazy/util/clock.h"
//#include "utils.h"


#include "perf_counters.h"
struct Monitor_Event inst_Monitor_Event = {
  {
    {0x2e,0x41},
    {0x24,0x21},
    {0xc5,0x00},
    {0x24,0x41},
  },
  1,
  {
    "L3 cache misses: ",
    "L2 cache misses: ",
    "Mispredicted branchs: ",
    "L2 cache hits: ",
  },
  {
    {0,0},
    {0,0},
    {0,0},
    {0,0},    
  },
  2,
  {
    "MIC_0",
    "MIC_1",
    "MIC_2",
    "MIC_3",
  },
    0  
};
*/



using namespace std;

inline size_t GetStartIndex(size_t total, unsigned tid, unsigned nthreads) {
  return (total / nthreads) * tid;
}

/*! Returns the ending index + 1 for the given thread to use
 * Loop using for (size_t i = GetStartIndex; i < GetEndIndex(); i++)
 * \param total the total number of examples
 * \param tid the thread id [0, 1, 2, ...]
 * \param total number of threads
 * \return last index to process PLUS ONE
 */
inline size_t GetEndIndex(size_t total, unsigned tid, unsigned nthreads) {
  size_t block_size = total / nthreads;
  size_t start = block_size * tid;
  if (nthreads == tid+1) {
    return total;
  }
  if (start + block_size > total) {
    return total;
  }
  return start + block_size;
}


////////////////////////Zip_sgd constructor/////////////////////
zipml_sgd_pm::zipml_sgd_pm(bool usingFPGA, uint32_t _b_toIntegerScaler) {

	srand(7); //for whta..

	dr_a  = NULL;  dr_a_norm = NULL; a_bitweaving_fpga = NULL; 
	dr_bi = NULL; dr_bi   = NULL;

	dr_a_min = NULL; dr_a_max = NULL; 

	dr_numFeatures = 0;
	dr_numSamples  = 0;
	dr_numBits	   = 0;

	b_toIntegerScaler = _b_toIntegerScaler;
	
	if (usingFPGA)
	{
		if (gotFPGA == 0) {  //1: should be this one...
			//myfpga = new FPGA();
			gotFPGA = 1;
		}
		else
			gotFPGA = 0;			
	}

}

////////////////////////Zip_sgd destructor/////////////////////
zipml_sgd_pm::~zipml_sgd_pm() {
	if (dr_a != NULL)
		free(dr_a);

	//if (dr_a_norm != NULL)
	//	free(dr_a_norm);
    //How to 

	if (dr_a_min != NULL)
		free(dr_a_min);

	if (dr_a_max != NULL)
		free(dr_a_max);

	if (dr_b != NULL)
		free(dr_b);

	if (dr_bi != NULL)
		free(dr_bi);

//	if (gotFPGA == 1) //should delete the class....
//		delete myfpga;
/**/		
}
/*
void zipml_sgd_pm::load_dense_data(char* pathToFile, uint32_t numSamples, uint32_t numFeatures)
{
	cout << "Reading " << pathToFile << endl;

	dr_numSamples 		= numSamples;
	dr_numFeatures		= numFeatures; // For the bias term
	dr_numFeatures_algin= ((dr_numFeatures+63)&(~63));


	dr_a 				= (float*)malloc(numSamples*numFeatures*sizeof(float)); 
	if (dr_a == NULL)
	{
		printf("Malloc dr_a failed in load_tsv_data\n");
		return;
	}

	dr_b 				= (float*)malloc(numSamples*sizeof(float));
	if (dr_b == NULL)
	{
		printf("Malloc dr_b failed in load_tsv_data\n");
		return;
	}

	dr_bi 				= (int*)malloc(numSamples*sizeof(int));
	if (dr_bi == NULL)
	{
		printf("Malloc dr_bi failed in load_tsv_data\n");
		return;
	}

	int zk_fd_src;
	zk_fd_src = open(pathToFile, O_RDWR);
	if (zk_fd_src == NULL) {
		printf("Cannot open the file with the path: %s\n", pathToFile);
	}
    //store the data to this address.        //Try to mapp the file to the memory region (zk_disk_addr, zk_total_len).
    float* source =  (float *)mmap (0, 8L*1024*1024*1024, PROT_READ|PROT_WRITE, MAP_SHARED, zk_fd_src, 0); //|MAP_HUGETLB
    if (source == MAP_FAILED) 
    {
        perror ("mmap the file error:../data/imagenet_8G_4M.dat ");
        return;
    }



	for (uint64_t i = 0; i < (1L * dr_numSamples * dr_numFeatures); i++) 
	{ // Bias term
		dr_a[i] = source[i];
	}

	//fclose(f);

	for (int i = 0; i < dr_numSamples; i++) { // Bias term
		dr_b[i] = ( ( (i%2) == 1)? 1.0:0.0); // 10 1.0:0.0 
	}

	cout << "numSamples: "  << dr_numSamples  << endl;
	cout << "numFeatures: " << dr_numFeatures << endl;


}*/


void mlweaving_on_sample(uint32_t *dest, uint32_t *src, uint32_t numSamples, uint32_t numFeatures)
{
	uint32_t address_index         = 0;
	//for(int i=0;i<100;i++){
	//	cout << "src:" << src[i] << endl;
	//}
	///Do the bitWeaving to the training data...
	for (uint32_t i = 0; i < numSamples; i+=NUM_BANKS)
	{
		uint32_t samples_in_batch = ( (i+NUM_BANKS)<numSamples )? NUM_BANKS:(numSamples-i);
		// j; //Deal with the main part of numFeatures.
		for (uint32_t j = 0; j < numFeatures; j += BITS_OF_BANK)//(numFeatures/BITS_OF_BANK)*BITS_OF_BANK
		{
			uint32_t bits_in_batch = ( (j+BITS_OF_BANK)<numFeatures )? BITS_OF_BANK:(numFeatures-j);
			uint32_t tmp_buffer[512] = {0};
			//1: initilization off tmp buffer..
			for (int k = 0; k < samples_in_batch; k++)//NUM_BANKS
				for (int m = 0; m < bits_in_batch; m++) //BITS_OF_BANK
					tmp_buffer[ k*BITS_OF_BANK+m ] = src[ (i + k)*numFeatures + (j+m) ];

			//2: focus on the data from index: j...
			for (int k = 0; k < 32; k++)
			{
				uint32_t result_buffer[16] = {0};
				//2.1: re-order the data according to the bit-level...
				for (int m = 0; m < 512; m++)
				{
					result_buffer[m>>5] = result_buffer[m>>5] | ((tmp_buffer[m] >>31)<<(m&31));
					tmp_buffer[m]       = tmp_buffer[m] << 1;
				}
			    //2.2: store the bit-level result back to the memory...
				dest[address_index++] = result_buffer[0];
				dest[address_index++] = result_buffer[1];
				dest[address_index++] = result_buffer[2];
				dest[address_index++] = result_buffer[3];
				dest[address_index++] = result_buffer[4];
				dest[address_index++] = result_buffer[5];
				dest[address_index++] = result_buffer[6];
				dest[address_index++] = result_buffer[7];
				dest[address_index++] = result_buffer[8];
				dest[address_index++] = result_buffer[9];
				dest[address_index++] = result_buffer[10];
				dest[address_index++] = result_buffer[11];
				dest[address_index++] = result_buffer[12];
				dest[address_index++] = result_buffer[13];
				dest[address_index++] = result_buffer[14];
				dest[address_index++] = result_buffer[15];
			}
		}
	}
	//for(int i=0;i<100;i++){
	//	cout << "dest:" << dest[i] << endl;
	//}
}

void mlweaving_change(uint32_t *dest, uint32_t *src, uint32_t numSamples, uint32_t numFeatures,uint32_t numBits,int worker_index)
{
// #define BITS_OF_CL      256
// #define NUM_BANKS       8
// #define BITS_OF_BANK    (BITS_OF_CL/NUM_BANKS)
// #define ENGINE_NUM		32
// #define BITS_NUM		8
	//  ofstream fpd;
	//  fpd.open("../../../distribute_data/d.txt",ios::out);
	
    //  if(!fpd.is_open ())
    //      cout << "Open file failure" << endl;

		
	


	uint32_t numFeatures_algin = ((numFeatures+63)&(~63));
	uint32_t address_index = 0;
	uint32_t dimension_num = ((numFeatures)%(BITS_OF_BANK*ENGINE_NUM*WORKER_NUM*2) == 0)? (numFeatures)/(BITS_OF_BANK*ENGINE_NUM*WORKER_NUM*2) : (numFeatures)/(BITS_OF_BANK*ENGINE_NUM*WORKER_NUM*2) + 1;
	uint32_t dimension_align = dimension_num*BITS_OF_BANK*ENGINE_NUM*WORKER_NUM*2;
	std::cout << "-----numSamples " << numSamples << " dimension_align " << dimension_align << endl;
	for (uint32_t i = 0; i < numBits; i+=2){
		for(uint32_t j = worker_index; j < ENGINE_NUM*WORKER_NUM; j = j + WORKER_NUM){
		for(uint32_t jj = 0; jj < 2; jj++){
			for(uint32_t k = 0; k < numSamples; k = k + NUM_BANKS){
				for(uint32_t l = j*BITS_OF_BANK; l < dimension_align; l = l + (ENGINE_NUM * WORKER_NUM * BITS_OF_BANK)){
					// fpd <<  "--sample: " << k << "address_index " << address_index <<endl;
					if(jj == 0){
						for(uint32_t m = 0;m < 8;m++){
							if(l < numFeatures){
								dest[address_index++] = src[(i + 1 + (l)/2 + numFeatures_algin*k/16)*16+m];
								// if(address_index < 100){
								// 	std::cout << "address: "<< address_index <<"src_index: " << (i + (l + j * BITS_OF_BANK)/2 + dimension_align*k/16)*16+m << endl;
								// 	// std::cout << " i " << i << " j " << j << " k "
								// }
							}
							else
							{
								dest[address_index++] = 0;
							}							
						}	
						for(uint32_t m = 0;m < 8;m++){
							if(l < numFeatures){
								dest[address_index++] = src[(i + (l)/2 + numFeatures_algin*k/16)*16+m];
							}
							else
							{
								dest[address_index++] = 0;
							}
						}	
					}
					else{
						for(uint32_t m = 8;m < 16;m++){
							if(l < numFeatures){
								dest[address_index++] = src[(i + 1 + (l)/2 + numFeatures_algin*k/16)*16+m];
							}
							else
							{
								dest[address_index++] = 0;
							}
						}	
						for(uint32_t m = 8;m < 16;m++){
							if(l < numFeatures){
								dest[address_index++] = src[(i + (l)/2 + numFeatures_algin*k/16)*16+m];
							}
							else
							{
								dest[address_index++] = 0;
							}
						}											
					}
				}
			}
		}
		}
	}
	std::cout << "address_final: "<< address_index<<std::endl;
	// fpd.close();

}



/////////////Load the data from file with .tsv type////////////
void zipml_sgd_pm::load_tsv_data(char* pathToFile, uint32_t numSamples, uint32_t numFeatures) {
	cout << "Reading " << pathToFile << endl;

	dr_numSamples 		= numSamples;
	dr_numFeatures		= numFeatures; // For the bias term
	dr_a 				= (float*)malloc(numSamples*numFeatures*sizeof(float)); 
	if (dr_a == NULL)
	{
		printf("Malloc dr_a failed in load_tsv_data\n");
		return;
	}
	//////initialization of the array//////
	for (int i = 0; i < dr_numSamples*dr_numFeatures; i++)
		dr_a[i] = 0.0;

	dr_b 				= (float*)malloc(numSamples*sizeof(float));
	if (dr_b == NULL)
	{
		printf("Malloc dr_b failed in load_tsv_data\n");
		return;
	}

	dr_bi 				= (int*)malloc(numSamples*sizeof(int));
	if (dr_bi == NULL)
	{
		printf("Malloc dr_bi failed in load_tsv_data\n");
		return;
	}

	FILE* f;
	f = fopen(pathToFile, "r");
	if (f == NULL) {
		printf("Cannot open the file with the path: %s\n", pathToFile);
	}

	uint32_t sample;
	uint32_t feature;
	float value;
	while(fscanf(f, "%d\t%d\t%f", &sample, &feature, &value) != EOF) {
		if (feature == -2) {
			dr_b[sample]  = value;
			dr_bi[sample] = (int)(value*(float)b_toIntegerScaler);
		}
		else
			dr_a[sample*dr_numFeatures + (feature)] = value; //+1
	}
	fclose(f);

	//for (int i = 0; i < dr_numSamples; i++) { // Bias term
	//	dr_a[i*dr_numFeatures] = 1.0;
	//}

	cout << "numSamples: "  << dr_numSamples  << endl;
	cout << "numFeatures: " << dr_numFeatures << endl;
}

///////////Load the data from file with .libsvm type///////////
void zipml_sgd_pm::load_libsvm_data(char* pathToFile, uint32_t _numSamples, uint32_t _numFeatures, uint32_t _numBits) {
	cout << "Reading " << pathToFile << endl;

	dr_numSamples  = _numSamples;
	dr_numBits	   = _numBits;	
	dr_numFeatures = _numFeatures; // For the bias term

	dr_numFeatures_algin = ((dr_numFeatures+63)&(~63));

	dr_a  = (float*)malloc(dr_numSamples*dr_numFeatures*sizeof(float)); 
	cout<<dr_numSamples*dr_numFeatures<<endl;
	if (dr_a == NULL)
	{
		printf("Malloc dr_a failed in load_tsv_data\n");
		return;
	}
	cout << "dra " << endl;
	//////initialization of the array//////
	for (long i = 0; i < dr_numSamples*dr_numFeatures; i++){
		dr_a[i] = 0.0;
	}

	cout << "draa " << endl;
	dr_b  = (float*)malloc(dr_numSamples*sizeof(float));
	if (dr_b == NULL)
	{
		printf("Malloc dr_b failed in load_tsv_data\n");
		return;
	}
	cout << "drb " << endl;
	dr_bi = (int*)malloc(dr_numSamples *sizeof(int));
	if (dr_bi == NULL)
	{
		printf("Malloc dr_bi failed in load_tsv_data\n");
		return;
	}
	cout << "drbi " << endl;
	string line;
	ifstream f(pathToFile);

	int index = 0;
	if (f.is_open()) 
	{
		while( index < dr_numSamples ) 
		{
			// cout<<index<<endl;
			getline(f, line);
			int pos0 = 0;
			int pos1 = 0;
			int pos2 = 0;
			int column = 0;
			while ( pos2 != -1 ) //-1 (no bias...) //while ( column < dr_numFeatures ) 
			{
				if (pos2 == 0) 
				{
					
					pos2 = line.find(" ", pos1);
					float temp = stof(line.substr(pos1, pos2-pos1), NULL);
					
					dr_b[index] = temp;
					dr_bi[index] = (int)(temp*(float)b_toIntegerScaler);
					// cout << "dr_b: "  << temp << endl;
				}
				else 
				{
					pos0 = pos2;
					pos1 = line.find(":", pos1)+1;
					if(pos1==0){
						break;
					}
					// cout<<"pos:"<<pos1<<endl;
					pos2 = line.find(" ", pos1);
					column = stof(line.substr(pos0+1, pos1-pos0-1));
					if (pos2 == -1) 
					{
						pos2 = line.length()+1;
						dr_a[index*dr_numFeatures + column-1] = stof(line.substr(pos1, pos2-pos1), NULL);
					}
					else{
						dr_a[index*dr_numFeatures + column-1] = stof(line.substr(pos1, pos2-pos1), NULL);
					}
					// cout << "dr_a: "  << column << endl;
					//cout << "index*dr_numFeatures + column: "  << index*dr_numFeatures + column-1 << endl;
					//cout << "dr_a[index*dr_numFeatures + column]: "  << dr_a[index*dr_numFeatures + column-1] << endl;
				}
			}
			index++;
		}
		f.close();
	}
	else
		cout << "Unable to open file " << pathToFile << endl;

	cout << "in libsvm, numSamples: "  << dr_numSamples << endl;
	cout << "in libsvm, numFeatures: " << dr_numFeatures << endl; 
	cout << "in libsvm, dr_numFeatures_algin: " << dr_numFeatures_algin << endl; 
}

///////////Load the data from file with .libsvm type///////////
void zipml_sgd_pm::load_synthesized_data(uint32_t _numSamples, uint32_t _numFeatures) {

	/* initialize random seed: */
	srand (time(NULL));

	dr_numSamples        = _numSamples;
	dr_numFeatures       = _numFeatures; // For the bias term
	dr_numFeatures_algin = ((dr_numFeatures+63)&(~63));

	dr_a  = (float*)malloc(dr_numSamples*dr_numFeatures*sizeof(float)); 
	if (dr_a == NULL)
	{
		printf("Malloc dr_a failed in load_tsv_data\n");
		return;
	}
	//////initialization of the a to random value...//////
	for (int i = 0; i < dr_numSamples*dr_numFeatures; i++)
		dr_a[i] = (float)(rand()) /(float) RAND_MAX;//0.0;

	dr_b  = (float*)malloc(dr_numSamples*sizeof(float));
	if (dr_b == NULL)
	{
		printf("Malloc dr_b failed in load_tsv_data\n");
		return;
	}

	dr_bi = (int*)malloc(dr_numSamples *sizeof(int));
	if (dr_bi == NULL)
	{
		printf("Malloc dr_bi failed in load_tsv_data\n");
		return;
	}
	//////initialization of the b to random value...//////

	for (uint64_t i = 0; i < dr_numSamples; i++)
	{
		float temp    = (i&1 == 1)?0.0:1.0;
		dr_b[i]       = temp;
		dr_bi[i]      = (int)(temp*(float)b_toIntegerScaler);

	}

	//for (int i = 0; i < dr_numSamples; i++) { // Bias term
	//	dr_a[i*dr_numFeatures] = 1.0;
	//}
	cout << "in synthesized_data, numSamples:           " << dr_numSamples << endl;
	cout << "in synthesized_data, numFeatures:          " << dr_numFeatures << endl;
	cout << "in synthesized_data, dr_numFeatures_algin: " << dr_numFeatures_algin << endl; 

}


///////////Load the data from file with .libsvm type///////////
void zipml_sgd_pm::load_libsvm_data_1(char* pathToFile, uint32_t _numSamples, uint32_t _numFeatures) {
	cout << "Reading " << pathToFile << endl;

	dr_numSamples        = _numSamples;
	dr_numFeatures       = _numFeatures; // For the bias term
	dr_numFeatures_algin = ((dr_numFeatures+63)&(~63));

	dr_a  = (float*)malloc(dr_numSamples*dr_numFeatures*sizeof(float)); 
	if (dr_a == NULL)
	{
		printf("Malloc dr_a failed in load_tsv_data\n");
		return;
	}
	//////initialization of the array//////
	for (int i = 0; i < dr_numSamples*dr_numFeatures; i++)
		dr_a[i] = 0.0;

	dr_b  = (float*)malloc(dr_numSamples*sizeof(float));
	if (dr_b == NULL)
	{
		printf("Malloc dr_b failed in load_tsv_data\n");
		return;
	}

	dr_bi = (int*)malloc(dr_numSamples *sizeof(int));
	if (dr_bi == NULL)
	{
		printf("Malloc dr_bi failed in load_tsv_data\n");
		return;
	}

	string line;
	ifstream f(pathToFile);

	int index = 0;
	if (f.is_open()) {
		while( index < dr_numSamples ) {
			getline(f, line);
			int pos0 = 0;
			int pos1 = 0;
			int pos2 = 0;
			int column = 0;
			//while ( column < dr_numFeatures-1 ) {
			while ( pos2 < line.length()+1 ) {
				if (pos2 == 0) {
					pos2 = line.find(" ", pos1);
					float temp = stof(line.substr(pos1, pos2-pos1), NULL);
					dr_b[index] = temp;
					dr_bi[index] = (int)(temp*(float)b_toIntegerScaler);
				}
				else {
					pos0 = pos2;
					pos1 = line.find(":", pos1)+1;
					pos2 = line.find(" ", pos1);
					column = stof(line.substr(pos0+1, pos1-pos0-1)); //stof
					if (pos2 == -1) {
						pos2 = line.length()+1;
						dr_a[index*dr_numFeatures + column] = stof(line.substr(pos1, pos2-pos1), NULL);
					}
					else
						dr_a[index*dr_numFeatures + column] = stof(line.substr(pos1, pos2-pos1), NULL);
				}
			}
			index++;
		}
		f.close();
	}
	else
		cout << "Unable to open file " << pathToFile << endl;

	//for (int i = 0; i < dr_numSamples; i++) { // Bias term
	//	dr_a[i*dr_numFeatures] = 1.0;
	//}
	cout << "in libsvm, numSamples: "           << dr_numSamples << endl;
	cout << "in libsvm, numFeatures: "          << dr_numFeatures << endl;
	cout << "in libsvm, dr_numFeatures_algin: " << dr_numFeatures_algin << endl; 

}


///////////Load the data from file with .libsvm type///////////
void zipml_sgd_pm::load_libsvm_data_int(char* pathToFile, uint32_t _numSamples, uint32_t _numFeatures) {
	cout << "Reading " << pathToFile << endl;

	dr_numSamples        = _numSamples;
	dr_numFeatures       = _numFeatures; // For the bias term
	dr_numFeatures_algin = ((dr_numFeatures+63)&(~63));

	dr_a  = (float*)malloc(dr_numSamples*dr_numFeatures*sizeof(float)); 
	if (dr_a == NULL)
	{
		printf("Malloc dr_a failed in load_tsv_data\n");
		return;
	}
	//////initialization of the array//////
	for (int i = 0; i < dr_numSamples*dr_numFeatures; i++)
		dr_a[i] = 0.0;

	dr_b  = (float*)malloc(dr_numSamples*sizeof(float));
	if (dr_b == NULL)
	{
		printf("Malloc dr_b failed in load_tsv_data\n");
		return;
	}

	dr_bi = (int*)malloc(dr_numSamples *sizeof(int));
	if (dr_bi == NULL)
	{
		printf("Malloc dr_bi failed in load_tsv_data\n");
		return;
	}

	string line;
	ifstream f(pathToFile);

	int index = 0;
	if (f.is_open()) {
		while( index < dr_numSamples ) {
			getline(f, line);
			int pos0 = 0;
			int pos1 = 0;
			int pos2 = 0;
			int column = 0;
			//while ( column < dr_numFeatures-1 ) {
			while ( pos2 < line.length()+1 ) {
				if (pos2 == 0) {
					pos2 = line.find(" ", pos1);
					float temp = stof(line.substr(pos1, pos2-pos1), NULL);
					dr_b[index] = temp;
					dr_bi[index] = (int)(temp*(float)b_toIntegerScaler);
				}
				else {
					pos0 = pos2;
					pos1 = line.find(":", pos1)+1;
					pos2 = line.find(" ", pos1);
					column = stof(line.substr(pos0+1, pos1-pos0-1)); //stof
					if (pos2 == -1) {
						pos2 = line.length()+1;
						dr_a[index*dr_numFeatures + column] = stof(line.substr(pos1, pos2-pos1), NULL);
					}
					else
						dr_a[index*dr_numFeatures + column] = stof(line.substr(pos1, pos2-pos1), NULL);
				}
			}
			index++;
		}
		f.close();
	}
	else
		cout << "Unable to open file " << pathToFile << endl;

	//for (int i = 0; i < dr_numSamples; i++) { // Bias term
	//	dr_a[i*dr_numFeatures] = 1.0;
	//}
	cout << "in libsvm, numSamples: "           << dr_numSamples << endl;
	cout << "in libsvm, numFeatures: "          << dr_numFeatures << endl;
	cout << "in libsvm, dr_numFeatures_algin: " << dr_numFeatures_algin << endl; 

}


///////////Load the data from file with .libsvm type///////////
void zipml_sgd_pm::load_libsvm_data_1_two(char* pathToFile, uint32_t _numSamples, uint32_t _numFeatures, uint32_t target_1, uint32_t target_2) {
	cout << "Reading " << pathToFile << endl;

	dr_numSamples        = _numSamples;
	dr_numFeatures       = _numFeatures; // For the bias term
	dr_numFeatures_algin = ((dr_numFeatures+63)&(~63));

	dr_a  = (float*)malloc(dr_numSamples*dr_numFeatures*sizeof(float)); 
	if (dr_a == NULL)
	{
		printf("Malloc dr_a failed in load_tsv_data\n");
		return;
	}
	//////initialization of the array//////
	for (int i = 0; i < dr_numSamples*dr_numFeatures; i++)
		dr_a[i] = 0.0;

	dr_b  = (float*)malloc(dr_numSamples*sizeof(float));
	if (dr_b == NULL)
	{
		printf("Malloc dr_b failed in load_tsv_data\n");
		return;
	}

	dr_bi = (int*)malloc(dr_numSamples *sizeof(int));
	if (dr_bi == NULL)
	{
		printf("Malloc dr_bi failed in load_tsv_data\n");
		return;
	}

	string line;
	ifstream f(pathToFile);

	int index      = 0;
	int real_index = 0; 
	bool skip_row  = false;

	if (f.is_open()) 
	{
		while( index < dr_numSamples ) 
		{
			getline(f, line);
			int pos0 = 0;
			int pos1 = 0;
			int pos2 = 0;
			int column = 0;

			skip_row   = false;
			//while ( column < dr_numFeatures-1 ) {
			while ( pos2 < line.length()+1 ) 
			{
				if (pos2 == 0) 
				{
					pos2 = line.find(" ", pos1);
					float temp = stof(line.substr(pos1, pos2-pos1), NULL);
					if ( (temp == (float)target_1) || (temp == (float)target_2) )
					{
						dr_b[real_index]  = temp;
						dr_bi[real_index] = (int)(temp*(float)b_toIntegerScaler);						
					}
					else
					{
						skip_row = true;
						break;
					}
				}
				else 
				{
					pos0 = pos2;
					pos1 = line.find(":", pos1)+1;
					pos2 = line.find(" ", pos1);
					column = stof(line.substr(pos0+1, pos1-pos0-1));
					if (pos2 == -1) {
						pos2 = line.length()+1;
						dr_a[real_index*dr_numFeatures + column] = stof(line.substr(pos1, pos2-pos1), NULL);
					}
					else
						dr_a[real_index*dr_numFeatures + column] = stof(line.substr(pos1, pos2-pos1), NULL);

					
				}
			}
			if (skip_row != true) 
				real_index++;

			index++;
		}
		f.close();
	}
	else
		cout << "Unable to open file " << pathToFile << endl;

	dr_numSamples = real_index;

	cout << "in libsvm, numSamples: "           << dr_numSamples << endl;
	cout << "in libsvm, numFeatures: "          << dr_numFeatures << endl;
	cout << "in libsvm, dr_numFeatures_algin: " << dr_numFeatures_algin << endl; 

}


//Normalize the training data to 0.xyz  x:0.5, y:0.25, z:0.125, so the FPGA can directly do the 
//the computation on the bit-level data representation. 
//Input: dr_a (from the input data...)
//Output: dr_a_norm (for the normalized result, also malloc the space for it...)
void zipml_sgd_pm::a_normalize(void) 
{

	//uint32_t *data  = reinterpret_cast<uint32_t*>( myfpga->malloc(100)); 
	dr_a_norm_fp = (float *)malloc(dr_numSamples*dr_numFeatures*sizeof(float)); 
	if (dr_a_norm_fp == NULL)
	{
		printf("Malloc dr_a_norm_fp failed in a_normalize\n");
		return;
	}

	//a_normalizedToMinus1_1 = toMinus1_1;
	dr_a_norm   = (uint32_t *)malloc(dr_numSamples*dr_numFeatures*sizeof(uint32_t)); //to store the normalized result....
	if (dr_a_norm == NULL)
	{
		printf("Malloc dr_a_norm failed in a_normalize\n");
		return;
	}

	dr_a_min    = (float *)malloc(dr_numFeatures*sizeof(float)); //to store the minimum value of features.....
	if (dr_a_min == NULL)
	{
		printf("Malloc dr_a_min failed in a_normalize\n");
		return;
	}

	dr_a_max    = (float *)malloc(dr_numFeatures*sizeof(float)); //to store the miaximum value of features.....
	if (dr_a_max == NULL)
	{
		printf("Malloc dr_a_max failed in a_normalize\n");
		return;
	}

	printf("dr_numFeatures = %d, dr_numSamples = %d, dr_numFeatures_algin = %d\n", dr_numFeatures, dr_numSamples, dr_numFeatures_algin);

	///Normalize the values in the whole column to the range {0, 1} or {-1, 1}/// 
	for (int j = 0; j < dr_numFeatures; j++) 
	{ // Don't normalize bias
		float amin = numeric_limits<float>::max();
		float amax = numeric_limits<float>::min();
		for (int i = 0; i < dr_numSamples; i++) 
		{
			float a_here = dr_a[i*dr_numFeatures + j];
			if (a_here > amax)
				amax = a_here;
			if (a_here < amin)
				amin = a_here;
		}
		dr_a_min[j]  = amin; //set to the global variable for pm
		dr_a_max[j]  = amax;

		float arange = amax - amin;
		if (arange > 0) 
		{
			for (int i = 0; i < dr_numSamples; i++) 
			{
				float tmp = ((dr_a[i*dr_numFeatures + j] - amin)/arange); //((dr_a[i*dr_numFeatures + j] - amin)/arange)*2.0-1.0;
			  	
			  	dr_a_norm_fp[i*dr_numFeatures + j] = tmp;
			  	dr_a_norm[i*dr_numFeatures + j]    = (uint32_t) (tmp * 4294967295.0); //4294967296 = 2^32
			  	//cout << "i*dr_numFeatures + j "  << i*dr_numFeatures + j << endl;
			  	//cout << "dr_a "  << dr_a[i*dr_numFeatures + j] << endl;
			  	//cout << "dr_a_norm_fp "  << dr_a_norm_fp[i*dr_numFeatures + j] << endl;
			  	//cout << "dr_a_norm "  << dr_a_norm[i*dr_numFeatures + j] << endl;
/*
				uint32_t tmp_buffer[4];
				( (float *)tmp_buffer )[0] = tmp;
				uint32_t exponent          = ( (tmp_buffer[0] >> 23) & 0xff);       //[30:23]
				uint32_t mantissa          = 0x800000 + (tmp_buffer[0]&0x7fffff); //[22:0 ]
				uint32_t result_before     = (mantissa << 8);

				if (exponent > 127)       //should be impossible...
				{	
					printf("The normalization value of a should be from 0 to 1.0\n");
					return; 
				}
				else if (exponent == 127) //for the case with value 1.0: 0xffff_ffff
					dr_a_norm[i*dr_numFeatures + j] = 0xffffffff;
				else 
					dr_a_norm[i*dr_numFeatures + j] = result_before >>(126-exponent);
*/					
			}
		}
	}
}

//Suppose each feature contains 32-bit value...
//With the default input is dr_numFeatures...
//Constraint: padding to the smallest power of two that's greater or equal to a given value (64, 128, 256)
uint32_t zipml_sgd_pm::compute_Bytes_per_sample() 
{
	return dr_numFeatures_algin*4;
	//With the chunk of 512 features...
	//uint32_t main_num           = (dr_numFeatures/BITS_OF_ONE_CACHE_LINE)*(BITS_OF_ONE_CACHE_LINE/8); //bytes
	//uint32_t rem_num            = 0;

	//For the remainder of dr_numFeatures...
	//uint32_t remainder_features = dr_numFeatures & (BITS_OF_ONE_CACHE_LINE - 1); 
	//if (remainder_features == 0)
	//	rem_num = 0;
	//else if (remainder_features <= 64)
	//	rem_num = 4;
	//else if (remainder_features <= 128)	
	//	rem_num = 8;
	//else if (remainder_features <= 256)	
	//	rem_num = 16;
	//else 	
	//	rem_num = 32;
	//return main_num + rem_num;
}
/*
void zipml_sgd_pm::a_perform_bitweaving_cpu(void) {

    //Compute the number of cache lines for each sample...
    int num_Bytes_per_sample = compute_Bytes_per_sample();

	printf("1 in a_perform_bitweaving_fpga, num_Bytes_per_sample = %d\n", num_Bytes_per_sample);

    //Compute the bytes for samples: Number of bytes for one CL        CLs                Samples
    uint64_t num_bytes_for_samples = num_Bytes_per_sample * ( (dr_numSamples+15)&(~15) ); //512;//
    printf("dr_numSamples = %d\n", dr_numSamples);

	a_bitweaving_cpu              = (uint32_t*) aligned_alloc(64, num_bytes_for_samples);  //(uint32_t*) malloc(num_bytes_for_samples);//
	if (a_bitweaving_cpu == NULL)
	{
		printf("Malloc memory space for a_bitweaving_cpu failed. \n");
		return;
	}

	hazy::vector::mlweaving_on_sample(a_bitweaving_cpu, dr_a_norm, dr_numSamples, dr_numFeatures); 

}
*/
//It performs the bitweaving operation on a_norm, which is 32-bit. 
//Input:  dr_a_norm (after normalization)
//Output: a_bitweaving_fpga (do the bit-weaving here...)
void zipml_sgd_pm::a_perform_bitweaving_fpga(int worker_index) {

    //printf("1 in a_perform_bitweaving_fpga\n");
    //sleep(1);

    //Compute the number of cache lines for each sample...
    int num_Bytes_per_sample = compute_Bytes_per_sample();

    //printf("2 in a_perform_bitweaving_fpga\n");
    //sleep(1);


    //Compute the bytes for samples: Number of bytes for one CL        CLs                Samples
    //uint64_t num_bytes_for_samples = num_Bytes_per_sample * dr_numSamples; //512;//
    uint64_t num_bytes_for_samples = (dr_numSamples%32 == 0) ? num_Bytes_per_sample * dr_numSamples : num_Bytes_per_sample * (dr_numSamples/32+1)*32; //512;//
    //printf("3 in a_perform_bitweaving_fpga\n");
    //sleep(1);
    a_bitweaving_distribute =  (uint32_t*) fpga::XDMA::allocate(1024*1024*1024);
	a_bitweaving_fpga              = reinterpret_cast<uint32_t*>(malloc(num_bytes_for_samples));  //(uint32_t*) malloc(num_bytes_for_samples);//
	if (a_bitweaving_fpga == NULL)
	{
		printf("Malloc FPGA memory space for a_bitweaving_fpga failed in a_perform_bitweaving_fpga. \n");
		return;
	}

    //printf("dr_numSamples = %d, dr_numFeatures = %d, num_bytes_for_samples = %ld\n", dr_numSamples, dr_numFeatures, num_bytes_for_samples);
    //sleep(1);
	mlweaving_on_sample(a_bitweaving_fpga, dr_a_norm, dr_numSamples, dr_numFeatures);

	// for(int i=0;i<1024*1024*128;i++){
	// 	a_bitweaving_fpga[i] = i;
	// }


	 ofstream fpa1;
	 int engine_index = 0;

	uint32_t numFeatures_algin = ((dr_numFeatures+63)&(~63));
	uint32_t dimension_num = (dr_numFeatures%(BITS_OF_BANK*ENGINE_NUM*2) == 0)? dr_numFeatures/(BITS_OF_BANK*ENGINE_NUM*2) : dr_numFeatures/(BITS_OF_BANK*ENGINE_NUM*2) + 1;
	uint32_t dimension_align = dimension_num*BITS_OF_BANK*ENGINE_NUM*2;	 

		// fpa1.open("../../../distribute_data/a1.txt",ios::out);
		
		// if(!fpa1.is_open ())
		// 	cout << "Open file failure" << endl;	 

		// for(uint32_t k = 0; k < dr_numSamples; k = k + NUM_BANKS){
		// 	for(uint32_t l = (engine_index)*BITS_OF_BANK; l < dimension_align; l = l + (ENGINE_NUM * BITS_OF_BANK)*2){
		// 		for(uint32_t i = 0; i < dr_numBits; i+=2){
		// 			for(int j=15;j >= 0;j--){
		// 				fpa1 << hex << setw(8) << setfill('0') << uint(a_bitweaving_fpga[(i + (l)/2 + numFeatures_algin*k/16)*16+j]);
		// 			}
		// 			fpa1 <<endl;
		// 			for(int j=15;j >= 0;j--){
		// 				fpa1 << hex << setw(8) << setfill('0') << uint(a_bitweaving_fpga[(i+1 + (l)/2 + numFeatures_algin*k/16)*16+j]);
		// 			}
		// 			fpa1 <<endl;	
		// 			for(int j=15;j >= 0;j--){
		// 				fpa1 << hex << setw(8) << setfill('0') << uint(a_bitweaving_fpga[(i + (l+(ENGINE_NUM * BITS_OF_BANK))/2 + numFeatures_algin*k/16)*16+j]);
		// 			}
		// 			fpa1 <<endl;
		// 			for(int j=15;j >= 0;j--){
		// 				fpa1 << hex << setw(8) << setfill('0') << uint(a_bitweaving_fpga[(i+1 + (l+(ENGINE_NUM * BITS_OF_BANK))/2 + numFeatures_algin*k/16)*16+j]);
		// 			}
		// 			fpa1 <<endl;														
		// 		}

		// 	}
			
		// }


		// fpa1.close();		 







	// dr_numSamples = 32;
	// dr_numFeatures = 256;
	
	cout << "num_bytes_for_samples " << num_bytes_for_samples << endl;
	mlweaving_change(a_bitweaving_distribute, a_bitweaving_fpga, dr_numSamples, dr_numFeatures, dr_numBits, worker_index);



	// for(int i=0;i<100;i++){
	// 	for(int j=0;j<16;j++){
	// 		cout << a_bitweaving_fpga[i*16+j] << " ";
	// 	}
	// 	cout << endl;
	// }

	// for(int i=0;i<100;i++){
	// 	for(int j=0;j<16;j++){
	// 		cout << a_bitweaving_distribute[i*16+j] << " ";
	// 	}	
	// 	cout << endl;
	// }

	//  ofstream fpa;
	//  fpa.open("../../../distribute_data/a.txt",ios::out);
	
    //  if(!fpa.is_open ())
    //      cout << "Open file failure" << endl;

	// for(int i = 0;i< dr_numSamples*dr_numFeatures_algin/16;i++){
	// 	for(int j=15;j >= 0;j--){
	// 		fpa << hex << setw(8) << setfill('0') << uint(a_bitweaving_distribute[i*16+j]);
	// 	}
	// 	fpa <<endl;
	// }
	// fpa.close();

	// ofstream fpb;
	//  fpb.open("/home/cj/distribute_sw/sw/b.txt",ios::out);
	
    //  if(!fpb.is_open ())
    //      cout << "Open file failure" << endl;

	// for(int i = 0;i< dr_numSamples*dr_numFeatures_algin;i++){
	// 	fpb << hex << uint(a_bitweaving_distribute[i]) <<endl;
	// }
	// fpb.close();


}

void zipml_sgd_pm::b_normalize(char toMinus1_1, char binarize_b, int shift_bits) 
{
	//b_normalizedToMinus1_1 = toMinus1_1;
	// for (int i = 0; i < 10; i++){
	// 	cout << "dr_b before "  << dr_b[i] << endl;
	// 	cout << "dr_bi before "  << dr_bi[i] << endl;
	// }
	/*if (binarize_b == 100)
	{
		for (int i = 0; i < dr_numSamples; i++) 
		{
			if( ((int)dr_b[i])%2  == 1 )
				dr_b[i] = 1.0;
			else
				dr_b[i] = 0.0;
	
			dr_bi[i] = ( ((int)dr_b[i])<<shift_bits ); //(int)(dr_b[i]*(float)b_toBinarizeTo);
		}
	}
	else
	{
		for (int i = 0; i < dr_numSamples; i++) 
		{
			if(dr_b[i] == (float)binarize_b)
				dr_b[i] = 1.0;
			else
				dr_b[i] = 0.0;
	
			dr_bi[i] = ( ((int)dr_b[i])<<shift_bits ); //(int)(dr_b[i]*(float)b_toBinarizeTo);
		}
	}*/

	dr_b_min   =  0.0;
	dr_b_range =  1.0;

}

void zipml_sgd_pm::b_copy_to_fpga(void)
{
	bi_fpga  = reinterpret_cast<uint32_t*>(malloc(dr_numSamples*sizeof(int)));
	if (bi_fpga == NULL)
	{
		printf("Malloc FPGA-accessable memory space (size: %lu) failed in b_copy_to_fpga\n", dr_numSamples*sizeof(int) );
	}

	//copy the dr_dr_bi to bi_fpga...
	for (int i = 0; i < dr_numSamples; i++)
	{
		bi_fpga[i] = dr_bi[i];
	}

	// ofstream fpb;
	// fpb.open("../../../distribute_data/b.txt",ios::out);
	
    //  if(!fpb.is_open ())
    //      cout << "Open file failure" << endl;

	// for(int i = 0;i< dr_numSamples;i++){
	// 	fpb << hex << uint(bi_fpga[i]) <<endl;
	// }
	// fpb.close();
}



// Provide: float x[numFeatures]
void zipml_sgd_pm::bitFSGD(fpga::XDMAController* controller,uint32_t number_of_bits, uint32_t numberOfIterations, uint32_t mini_batch_size, uint32_t stepSize, int binarize_b, float b_toBinarizeTo,int node_index,int server_en) 
{
    /////1:::Setup FPGA/////
    //1.1: set up afu augument configuration for the SGD on FPGA
	// ofstream fpa;
	// ofstream fpb;
	// fpa.open("/home/ccai/MLWeaving/mlweaving_hls/a.txt",ios::out);
	// fpb.open("/home/ccai/MLWeaving/mlweaving_hls/b.txt",ios::out);
	
    // if(!fpa.is_open ())
    //     cout << "Open file failure" << endl;
	
		
    // if(!fpb.is_open ())
    //     cout << "Open file failure" << endl;


    /*if (afu_cfg == NULL)
    {
    	printf("Malloc afu_cfg in the FPGA memory space failed in bitFSGD\n");
    	return;
    }*/

	dr_numFeatures_algin = ((dr_numFeatures+63)&(~63));
	x_fpga = reinterpret_cast<int*>(malloc(sizeof(int) * numberOfIterations * dr_numFeatures_algin ) );   //((dr_numFeatures+63)&(~63))
    if (x_fpga == NULL)
    {
    	printf("Malloc x_fpga in the FPGA memory space failed in bitFSGD\n");
    	return;
    }

    printf("before step_shifter = %d\n", stepSize);
    uint32_t mini_batch_size_tmp = mini_batch_size;

    while (mini_batch_size_tmp >>= 1)
    	stepSize++;
    printf("after step_shifter = %d\n", stepSize);

	uint64_t addr_a,addr_b,addr_model;
	uint32_t dimension,number_of_samples,data_a_length,data_b_length,array_length,channel_num;
	uint32_t dimension_num;
	addr_a = (uint64_t)a_bitweaving_distribute;
   	addr_b = (uint64_t)(&a_bitweaving_distribute[1024*1024*500]);
   	addr_model = (uint64_t)(&a_bitweaving_distribute[1024*1024*900]);	
	for(int i=0;i<dr_numSamples/16;i++){
		for(int j=0;j<16;j++){
			if(j<8)
				a_bitweaving_distribute[1024*1024*500 + i*16 + j] = bi_fpga[i*16 + j + 8];
			else
			{
				a_bitweaving_distribute[1024*1024*500 + i*16 + j] = bi_fpga[i*16 + j - 8];/* code */
			}
			
		}		
	}



	dimension                   = dr_numFeatures/WORKER_NUM;    
	number_of_samples           = dr_numSamples;

   number_of_samples           = (number_of_samples % 32) == 0 ?number_of_samples : (number_of_samples/32 + 1)*32;   //write to hbm 4 cache line b_data = 32 samples 
   dimension_num               = (dimension%((512/NUM_BANKS)*ENGINE_NUM*WORKER_NUM*2) == 0)? dimension/((512/NUM_BANKS)*ENGINE_NUM*WORKER_NUM*2) : dimension/((512/NUM_BANKS)*ENGINE_NUM*WORKER_NUM*2) + 1;
   data_a_length               = (number_of_samples/NUM_BANKS) * dimension_num * (number_of_bits/2) * ENGINE_NUM * 4 * 32 * 2;
   array_length                = (number_of_samples/NUM_BANKS) * dimension_num * 4 * 32;
   array_length                = (array_length%4096 == 0)? (array_length + 1024):( (array_length/4096 + 1)*4096 + 1024);
   channel_num                 = 0;
   data_b_length			   = number_of_samples *8;	
   if(channel_num != 32){
	   data_b_length = data_a_length/ENGINE_NUM;
   }


	cout << "number_of_samples: " << number_of_samples << endl;
	cout << "dimension: " << dimension << endl;
	cout << "number_of_bits: " << number_of_bits << endl;
	cout << "data_a_length: " <<hex<< data_a_length << endl;
	cout << "array_length: " <<hex<< array_length << endl;
	cout << "channel_num: " << channel_num << endl;
	cout << "dimension_num: " << dimension_num << endl;
	cout << "numberOfIterations: " << numberOfIterations << endl;



   int mac = node_index;
   int ip_addr = 0xc0a8bd00 + node_index;
   int listen_port = 1235;
   int conn_ip;
   int worker_ip[WORKER_NUM];
//    if(node_index == 0){
//       conn_ip = 0xc0a8bd01;
//    }
//    else{
      conn_ip = 0xc0a8bd01;
//    }

	worker_ip[0] = 0xc0a8bd02;
	worker_ip[1] = 0xc0a8bd04;
	worker_ip[2] = 0xc0a8bd05;
	worker_ip[3] = 0xc0a8bd08;
	worker_ip[4] = 0xc0a8bd05;
	worker_ip[5] = 0xc0a8bd06;
	worker_ip[6] = 0xc0a8bd07;
	worker_ip[7] = 0xc0a8bd08;


   
   
   cout << "mac" << node_index<< endl;
   cout << "ip_addr" << ip_addr<< endl;
   cout << "conn_ip" << conn_ip<< endl;

   int conn_port = 1235;
   int session_id;

   controller->writeReg(0, 0);
   controller->writeReg(0, 1);
   sleep(1);
//    controller ->writeReg(180,(controller->readReg(658)));
   controller->writeReg(128, (uint32_t)mac);
   controller->writeReg(129, (uint32_t)ip_addr);
   controller->writeReg(130, (uint32_t)listen_port);

   controller->writeReg(132, (uint32_t)conn_ip);
   controller->writeReg(133, (uint32_t)conn_port);

   controller->writeReg(144, (uint32_t)worker_ip[0]);
   controller->writeReg(145, (uint32_t)worker_ip[1]);
   controller->writeReg(146, (uint32_t)worker_ip[2]);
   controller->writeReg(147, (uint32_t)worker_ip[3]);
   controller->writeReg(148, (uint32_t)worker_ip[4]);
   controller->writeReg(149, (uint32_t)worker_ip[5]);
   controller->writeReg(150, (uint32_t)worker_ip[6]);
   controller->writeReg(151, (uint32_t)worker_ip[7]);

   controller->writeReg(131, (uint32_t)0);
   controller->writeReg(131, (uint32_t)1);

   cout << "listen status: " << controller->readReg(904) << endl;
   while (((controller->readReg(904)) >> 1) == 0)
   {
      sleep(1);
      cout << "listen status: " << controller->readReg(904) << endl;
   };
   cout << "listen status: " << controller->readReg(904) << endl;
   sleep(2);

if(server_en == 1){


   controller->writeReg(134, (uint32_t)0);
   controller->writeReg(134, (uint32_t)1);

   cout << "conn status: " << controller->readReg(905) << endl;
   while (((controller->readReg(905)) >> 16) == 0)
   {
      cout << "conn status: " << controller->readReg(905) << endl;
      sleep(1);
   };
   session_id = controller->readReg(905) & 0x0000ffff;
   cout << "session_id: " << session_id << endl;
   cout << "conn status: " << controller->readReg(905) << endl;
   sleep(1);
   controller->writeReg(134, (uint32_t)0);

}



	controller ->writeReg(20,addr_a);
	controller ->writeReg(21,addr_a >> 32);
	controller ->writeReg(22,addr_b);
	controller ->writeReg(23,addr_b >> 32);
	controller ->writeReg(24,addr_model);
	controller ->writeReg(25,addr_model >> 32);
	controller ->writeReg(26,mini_batch_size);
	controller ->writeReg(27,stepSize);
	controller ->writeReg(28,numberOfIterations);
	controller ->writeReg(29,dimension);
	controller ->writeReg(30,number_of_samples);
	controller ->writeReg(31,number_of_bits);
	controller ->writeReg(32,data_a_length);
	controller ->writeReg(33,array_length);
	controller ->writeReg(34,channel_num);
	controller ->writeReg(35,data_b_length);
	controller ->writeReg(36,0);
	controller ->writeReg(36,1);

	sleep(10);

	// controller ->writeReg(135,session_id);
	// controller ->writeReg(136,0);
	// controller ->writeReg(136,1);

	cout << "waddr_state: " << controller ->readReg(576)<< endl; 
	cout << "wdata_state: " << controller ->readReg(577)<< endl;
	cout << "dma_rd_cmd_cnt: " <<hex << controller ->readReg(525)<< endl;
	cout << "dma_rd_data_cnt: " <<hex << controller ->readReg(526)<< endl;
	cout << "hbm_wr_cycle_cnt: " <<hex << controller ->readReg(578)<< endl;
	cout << "hbm_wr_addr_cnt: " <<hex << controller ->readReg(579)<< endl;
	cout << "hbm_wr_data_cnt: " <<hex << controller ->readReg(580)<< endl;

	cout << "hbm_rd_addr_cnt0: " << hex << controller ->readReg(597)<< endl;
	cout << "hbm_rd_addr_cnt1: " << hex << controller ->readReg(598)<< endl;
	cout << "hbm_a_data_cnt: " << hex << controller ->readReg(613)<< endl;
	cout << "hbm_a_data_cnt: " << hex << controller ->readReg(614)<< endl;
	cout << "hbm_b_data_cnt: " << hex << controller ->readReg(629)<< endl;
	cout << "hbm_b_data_cnt: " << hex << controller ->readReg(630)<< endl;	

	cout << "dma_wr_cmd_cnt: " << hex << controller ->readReg(522)<< endl;
	cout << "dma_wr_data_cnt: " << hex << controller ->readReg(523)<< endl;

	cout << "a_data_cnt: " << controller ->readReg(815)<< endl;
	cout << "dot_product_cnt: " << controller ->readReg(808)<< endl;
	cout << "dot_product_state: " << controller ->readReg(768)<< endl;

	cout << "b_data_cnt: " << controller ->readReg(752)<< endl;
	cout << "a_minus_b_cnt: " << controller ->readReg(809)<< endl;
	cout << "gradient_cnt: " << controller ->readReg(776)<< endl;
	cout << "x_update_cnt: " << controller ->readReg(784)<< endl;
	cout << "x_cnt: " << controller ->readReg(800)<< endl;
	cout << "x_state: " << controller ->readReg(792)<< endl;

	cout << "x_mem_cmd_cnt: " << controller ->readReg(802)<< endl;
	cout << "x_mem_data_cnt: " << controller ->readReg(803)<< endl;

	cout << "done: " << controller ->readReg(810)<< endl;
	cout << "sgd_sum: " <<dec<< controller ->readReg(811)<< endl;
	cout << "delay_cnt: " <<dec<< controller ->readReg(812)<< endl;
	cout << "time: " <<dec<< controller ->readReg(813)<< endl;
	cout << "fifo_a_full: " <<dec<< controller ->readReg(814)<< endl;

	cout << "epoch0: " <<dec<< controller ->readReg(818)<< endl;
	cout << "epoch1: " <<dec<< controller ->readReg(819)<< endl;
	cout << "epoch1: " <<dec<< controller ->readReg(820)<< endl;
	cout << "epoch1: " <<dec<< controller ->readReg(821)<< endl;
	cout << "epoch1: " <<dec<< controller ->readReg(822)<< endl;

	float scale_f = (float)(1 << 23);
	ofstream fpc;
	 fpc.open("../../c.txt",ios::out);
	
     if(!fpc.is_open ())
         cout << "Open file failure" << endl;

	for(int i = 0;i< data_a_length/ENGINE_NUM/64;i++){
		for(int j=15;j >= 0;j--){
			fpc << hex << setw(8) << setfill('0') << uint(a_bitweaving_distribute[i*16+j+1024*1024*900]);
		}
		fpc << endl;
	}
	// for(int i=0;i<(numberOfIterations);i++){
	// 	for (int j = 0; j < dr_numFeatures; j++) {
	// 		fpc << "epoch: "<< numberOfIterations << "dr_numFeatures: " << dr_numFeatures << "x: "<< (float)(a_bitweaving_distribute[2097152 + j + i*dr_numFeatures])/scale_f << endl; //8388608.0  ;
	// 	}		
	// }


	fpc.close();


	int x_int[dr_numFeatures];
	float x_tmp[dr_numFeatures];
       memset( x_tmp, 0, dr_numFeatures*sizeof(float) );
	float loss_final;

	for(int i=0;i<(numberOfIterations+1);i++){
		for (int j = 0; j < dr_numFeatures; j++) {
			x_int[j] = a_bitweaving_distribute[1024*1024*900 + j + i*dr_numFeatures];
			x_tmp[j] = (float)(x_int[j])/scale_f; //8388608.0  ;
		}

		loss_final = calculate_loss(x_tmp);
		cout << "loss_final:" << loss_final << endl;		
	}
	



}


//pure software implementation on CPU...
void zipml_sgd_pm::float_linreg_SGD(uint32_t numberOfIterations, float stepSize) {

	dr_numFeatures_algin = ((dr_numFeatures+63)&(~63));
    x = (float *) malloc(sizeof(float)*numberOfIterations * dr_numFeatures_algin ); //numFeatures
	float x_tmp[dr_numFeatures_algin];
	for (int j = 0; j < dr_numFeatures_algin; j++) {
		x_tmp[j] = 0.0;
	}
	
	float loss_value = calculate_loss(x_tmp);
	cout << "init_loss: "<< loss_value <<endl;


	for(int epoch = 0; epoch < numberOfIterations; epoch++) {

		for (int i = 0; i < dr_numSamples; i++) {
			float dot = 0;
			for (int j = 0; j < dr_numFeatures; j++) {
				dot += x_tmp[j]*dr_a_norm_fp[i*dr_numFeatures + j];
			}
			
			//printf("dot = %f\n", dot);

			for (int j = 0; j < dr_numFeatures; j++) {
				x_tmp[j] -= stepSize*(dot - dr_b[i])*dr_a_norm_fp[i*dr_numFeatures + j];
			}


		}

		for (int j = 0; j < dr_numFeatures; j++) {
			x[epoch*dr_numFeatures + j] = x_tmp[j];

			//if (j < 10)
			//	printf("%d = %f\n", j, x_tmp[j]);
		}

		float loss_value = calculate_loss(x_tmp);
		cout << epoch << "_loss: "<< loss_value <<endl;
	}
}


//pure software implementation on CPU...
void zipml_sgd_pm::float_linreg_SGD_batch(uint32_t numberOfIterations, float stepSize, int mini_batch_size) {

	dr_numFeatures_algin = ((dr_numFeatures+63)&(~63));
	float temp;
    x = (float *) malloc(sizeof(float)*numberOfIterations * dr_numFeatures_algin ); //numFeatures

    float x_tmp[dr_numFeatures_algin];
	for (int j = 0; j < dr_numFeatures_algin; j++) 
		x_tmp[j] = 0.0;

    float x_gradient[dr_numFeatures_algin];
	for (int j = 0; j < dr_numFeatures_algin; j++) 
		x_gradient[j] = 0.0;
	
	float stepSize_in_use = stepSize/(float)mini_batch_size;
	//////Initialized loss...///
	float loss_value = calculate_loss(x_tmp);
	cout << "init_loss: "<< loss_value <<endl;


	ofstream fpe;
	 fpe.open("../../../distribute_data/e.txt",ios::out);
	
     if(!fpe.is_open ())
         cout << "Open file failure" << endl;

	float statisitcs;



	//Iterate over each epoch...
	for(int epoch = 0; epoch < numberOfIterations; epoch++) 
	{

		//for one mini_batch...
		for (int i = 0; i < (dr_numSamples/mini_batch_size)*mini_batch_size; i += mini_batch_size) 
		{
			///set the gradient to 0.
			for (int k = 0; k < dr_numFeatures_algin; k++){ 
				x_gradient[k] = 0.0;
			}
			///compute the gradient for this mini batch.
			for (int k = 0; k < mini_batch_size; k++)
			{
				float dot = 0;
				for (int j = 0; j < dr_numFeatures; j++) 
					dot += x_tmp[j]*dr_a_norm_fp[(i+k)*dr_numFeatures + j];

				statisitcs = dot - dr_b[i+k];

				for (int j = 0; j < dr_numFeatures; j++){
					x_gradient[j] += stepSize_in_use*statisitcs*dr_a_norm_fp[(i+k)*dr_numFeatures + j];
					//temp = x_gradient[j]*8388608;
					//cout << "x_gradient feature"  << j << "sample" << i+k << "--:"<< temp << endl;
				}
			}

			///update the model with the computed gradient..
			for (int k = 0; k < dr_numFeatures_algin; k++){
				x_tmp[k] -= x_gradient[k];
				//if(k<8)
				//cout << "x_tmp"  << k <<  "--:"<< x_tmp[k] << endl;
			}
		}


		//Store to the global model pool...
		for (int j = 0; j < dr_numFeatures; j++) {
			x[epoch*dr_numFeatures + j] = x_tmp[j];
			fpe << "epoch: "<< epoch << "dr_numFeatures: " << dr_numFeatures << "x: "<< x_tmp[j]<<endl; 
		}

		float loss_value = calculate_loss(x_tmp);
		cout << epoch << "_loss: "<< loss_value <<endl;
	}

	fpe.close();
}



float zipml_sgd_pm::calculate_loss(float x[]) {
 	//cout << "numSamples: "  << numSamples << endl;
	//cout << "numFeatures: " << numFeatures << endl;
    //numSamples  = 10;
	//cout << "For debugging: numSamples=" << numFeatures << endl;

	float loss = 0;
	for(int i = 0; i < dr_numSamples; i++) {
		float dot = 0.0;
		for (int j = 0; j < dr_numFeatures; j++) {
			dot += x[j]*dr_a_norm_fp[i*dr_numFeatures + j];
			//cout << "x["<< j <<"] =" << x[j] << "   a="<< a[i*numFeatures+ j];
		}
		loss += (dot - dr_b[i])*(dot - dr_b[i]);
		//cout << "b[i]" << b[i] << endl;
        //cout << loss << endl;
	}

	loss /= (float)(2*dr_numSamples);
	return loss;
}


void zipml_sgd_pm::compute_loss_and_printf(uint32_t numberOfIterations, uint32_t num_fractional_bits)
{
	float scale_f = (float)(1 << num_fractional_bits);
	float x_tmp[dr_numFeatures];
       memset( x_tmp, 0, dr_numFeatures*sizeof(float) );
	float loss_final = calculate_loss(x_tmp);
        printf("Before training, loss is %f\n", loss_final);

	for (uint32_t i = 0; i < numberOfIterations; i++)
	{
		for (int j = 0; j < dr_numFeatures; j++) {
			x_tmp[j] = (float)(x_fpga[i*dr_numFeatures_algin + j])/scale_f; //8388608.0  ;
		}

	        loss_final = calculate_loss(x_tmp);	
		printf("%d-th iteration, loss is %f\n", i, loss_final);
	}
}





//#endif
