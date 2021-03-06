#' A function to generate a sparse large document term matrix in blocks from a list document term vector lists stored as .Rdata object on disk. This function is designed to work on very large corpora (up to 10's of billions of words) that would otherwise be computationally intractable to generate a document term matrix for using standard methods. However, this function, and R itself, is limited to a vocaublary size of roughly 2.1 billion unique words.
#'
#' @param file_list A character vector of paths to intermediate files prefferably generated by the generate_document_term_vector_list() function, that reside in the file_directory or have their full path specified.
#' @param file_directory The directory where you have stored a series of intermediate .Rdata files, each of which contains an R list object named "document_term_vector_list" which is a list of document term vectors. This can most easily  be generated by the generate_document_term_vector_list() function. Defaults to NULL, in which case the current working directory will be used. This argument can also be left as NULL if the full path to the intermediate files you are using is provided.
#' @param vocabulary If we already know the aggregate vocabulary, then it can be provided as a string vector. When providing this vector it will be mush more computationally efficient to provide it order from most frequently appearing words to least frequently appearing ones for computational efficiency. Defaults to NULL in which case the vocabulary will be determined inside the function. The list object saved automatically in the Vocabulary.Rdata file in the file_directory may be provided (after first loading it into memory). This is the memory optimized object saved automatically if generate_sparse_term_matrix == FALSE.
#' @param maximum_vocabulary_size An integer specifying the maximum number of unique word types you expect to encounter. Defaults to -1 in which case the maximum vocabulary size used for pre-allocation in finding the common vocabular across all documents will be set to approximately the number of words in all documents. If you beleive this number to be over 2 billion, or are memory limited on your computer it is recommended to set this to some lower number. For normal english words, a value of 10 million should be sufficient. If you are dealing with n-grams then somewhere in the neighborhood of 100 million to 1 billion is often appropriate. If you have reason to believe that your final vocabulary size will be over ~2,147,000,000 then you should considder working in C++ or rolling your own functions, and congratuations, you have really large text data.
#' @param using_document_term_counts Defaults to FALSE, if TRUE then we epect a document_term_count_list for each chunk. See generate_document_term_matrix() for more information.
#' @param generate_sparse_term_matrix Defaults to TRUE. If FALSE, then the function only generates and saves the aggregate vocabulary (and counts) in the form of a list object named Aggregate_Vocabular_and_Counts.Rdata in file_directory or the current working directory if file_directory = NULL. This option is useful if we have an extremely large corpus and may wnat to trim the vocabulary first before providing an aggregate_vocabulary.
#' @param parallel Defaults to FALSE, but can be set to TRUE to speed up processing provided the machine hte user is using has enough RAM. Parallelization is currently implemented using forking in the parallel package (mclapply) so it will only work on UNIX based platforms..
#' @param cores Defaults to 1. Can be set to the number of cores on your computer.
#' @param large_vocabulary Defaults to FALSE. If the user believes their vocabulary to be greater than ~500,000 unique terms, specifying true may result in a substantial reduction in compute time. If TRUE, then the program implements a stemming lookup table to efficiently index terms in the vocabulary. This option only works with parallel = TRUE and is meant to accomodate vocabulary sizes up to several hundred million unique terms.
#' @param term_frequency_threshold The number of times a term must appear in the corpus or it will be removed. Defaults to 0. 5 is a reasonable choice, and higher numbers will speed computation by reducing vocabulary size.
#' @param save_vocabulary_to_file Defaults to FALSE. If TRUE, the the vocabulary file you generate will be saved to disk so that the process can be restarted later.
#' @return A sparse document term matrix object. This will likely still be a large file.
#' @export
generate_sparse_large_document_term_matrix <- function(file_list,
                                              file_directory = NULL,
                                              vocabulary = NULL,
                                              maximum_vocabulary_size = -1,
                                              using_document_term_counts = FALSE,
                                              generate_sparse_term_matrix = TRUE,
                                              parallel = FALSE,
                                              cores = 1,
                                              large_vocabulary = FALSE,
                                              term_frequency_threshold = 0,
                                              save_vocabulary_to_file = FALSE){
    # get the current working directory so we can change back to it.
    current_directory <- getwd()
    # change working directory file_directory
    if(!is.null(file_directory)){
        setwd(check_directory_name(file_directory))
    }
    # get a count of the number of intermediate files
    num_files <- length(file_list)
    cat("Generating sparse document term matrix from",num_files,"blocks.\n")
    if(num_files < 2){
        stop("This function expects N > 1 intermediate files in file_list. Either split this file into smaller constituents or use the generate_document_term_matrix() function.")
    }

    if(large_vocabulary & !is.null(vocabulary)){
        if(class(vocabulary) != "list"){
            stop("If you are providing a vocabulary object and have specified large_vocabulary = TRUE, then you must first load the list object saved automatically in the Vocabulary.Rdata file in the file_directory, and provide that list object, called 'vocabulary', as the vocabulary argument.")
        }
    }

    VOCAB_PROVIDED = FALSE
    if(!is.null(vocabulary)){
        VOCAB_PROVIDED = TRUE
        if(class(vocabulary) == "list"){
            if(vocabulary$type == "standard"){
                # all is well
            }else if(vocabulary$type == "stem-lookup"){
                # all is well
            }else{
                stop("You have provided a vocabulary in a list form. If you are providing your own vocabulary you must provide it as a character vector.")
            }
        }
    }

    # set global variable to NULL
    document_term_vector_list = NULL

    if(!using_document_term_counts){
        document_term_count_list = NULL
    }
    # otherwise we expect an object named document_term_count_list

    # if the user did not provide a vocabulary, then we have to generate one.
    if(is.null(vocabulary)){
        load(file_list[1])
        cat("Generating vocabulary from block 1 ...\n")
        vocab <- count_words(document_term_vector_list,
                             maximum_vocabulary_size = maximum_vocabulary_size,
                             existing_vocabulary = NULL,
                             existing_word_counts = NULL,
                             document_term_count_list = document_term_count_list)
        for(i in 2:num_files){
            load(file_list[i])
            cat("Generating vocabulary from block",i,"...\n")
            # If we are approaching the maximum vocabulary size then increase it by 50%
            if(maximum_vocabulary_size != -1){
                if(vocab$total_unique_words/maximum_vocabulary_size > 0.8){
                    maximum_vocabulary_size <- 1.5*maximum_vocabulary_size
                }
            }
            vocab <- count_words(document_term_vector_list,
                        maximum_vocabulary_size= maximum_vocabulary_size,
                        existing_vocabulary = vocab$unique_words,
                        existing_word_counts = vocab$word_counts,
                        document_term_count_list = document_term_count_list)
        }
        vocabulary <- list(vocabulary = vocab$unique_words,
                           type = "standard")

        # now lets generate the lookup if we specified large_vocabulary = TRUE
        if(large_vocabulary){
            #call the funtion which generates the large vocabulary
            vocabulary <- speed_set_vocabulary(
                vocab = vocab,
                term_frequency_threshold = term_frequency_threshold,
                cores = cores)
        }
    }

    # now get the aggregate vocabulary size
    aggregate_vocabulary_size <- length(vocabulary$vocabulary)
    cat("Aggregate vocabulary size:",aggregate_vocabulary_size,"\n")

    if(save_vocabulary_to_file & !VOCAB_PROVIDED){
        Aggregate_Vocabular_and_Counts <- vocab
        save(Aggregate_Vocabular_and_Counts,
             file = "Aggregate_Vocabular_and_Counts.Rdata")
        # save memory optimized object
        save(vocabulary, file = "Vocabulary.Rdata")
    }

    if(generate_sparse_term_matrix){
        if(!parallel){
            #loop over bill blocks to add to matricies
            for(j in 1:num_files){
                cat("Generating sparse matrix from block number:",j,"\n")
                load(file_list[j])

                current_document_lengths <- unlist(lapply(document_term_vector_list, length))

                cat("Total terms in current block:",sum(current_document_lengths),"\n")

                current_dw <- generate_document_term_matrix(
                    document_term_vector_list,
                    vocabulary = vocabulary,
                    document_term_count_list = document_term_count_list,
                    return_sparse_matrix = TRUE)

                #turn into simple triplet matrix and rbind to what we already have
                #current_dw <- slam::as.simple_triplet_matrix(current_dw)
                if(j == 1){
                    sparse_document_term_matrix <- current_dw
                }else{
                    sparse_document_term_matrix <- rbind(
                        sparse_document_term_matrix,
                        current_dw)
                }
            }
        }else{
            requireNamespace("slam")
            # if we are using parallel
            chunks <- ceiling(num_files/cores)
            counter <- 1
            start <- 1
            end <- min(cores,num_files)
            for(j in 1:chunks){
                # get indexing right
                cat("Currently working on files:",start, "to",end,"of", num_files,"\n")
                current_file_indexes <- start:end
                start <- start + cores
                end <- min(end + cores,num_files)

                cur_files <- file_list[current_file_indexes]
                cat("Applying Across Cluster ... \n")
                result <- parallel::mclapply(
                    cur_files,
                    sparse_doc_term_parallel,
                    vocabulary = vocabulary,
                    mc.cores = cores)
                # kill off any waiting cores
                # kill_zombies()
                cat("Cluster apply complete ... \n")
                for(k in 1:length(result)){
                    cat("Adding current block",k,"of",length(result),"to sparse matrix ... \n")
                    if(counter == 1){
                        temp <- result[[k]]
                        sparse_document_term_matrix <- temp
                    }else{
                        temp <- result[[k]]
                        sparse_document_term_matrix <- rbind(
                            sparse_document_term_matrix,
                            temp)
                        cat(str(sparse_document_term_matrix),"\n")
                    }
                    counter <- counter + 1
                }
                rm(result)
                gc()
            }
        }
        #reset working directory
        setwd(current_directory)
        #get the names right
        #colnames(sparse_document_term_matrix) <- aggregate_vocabulary
        if(large_vocabulary){
            ordering <- order(slam::col_sums(sparse_document_term_matrix), decreasing = T)
            sparse_document_term_matrix <- sparse_document_term_matrix[,ordering]
        }
        #print(str(sparse_document_term_matrix))
        return(sparse_document_term_matrix)
    }else{
        return(vocabulary)
    }
}
